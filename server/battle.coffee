{_} = require 'underscore'
{FakeRNG} = require './rng'
{Pokemon} = require './pokemon'
{Player} = require './player'
{Team} = require './team'
{Weather} = require './weather'

class @Battle
  # TODO: let Battle serialize these.
  {moves, MoveData, species, PokemonData} = require '../data/bw'

  constructor: (@id, attributes = {}) ->
    # Number of pokemon on each side of the field
    @numActive = 1

    # Stores the current turn of the battle
    @turn = 0

    # Stores the actions each player is about to make
    # Keyed by player.id
    @playerActions = {}

    # Stores the current requests for moves. Keyed by player.id
    @requests = {}

    # Stores queue of players that need to move.
    @requestQueue = []

    # Creates a RNG for this battle.
    @rng = new FakeRNG()

    # Maps clientId -> object
    @objectHash = {}

    # Current battle weather.
    @weather = Weather.NONE

    # Current turn duration for the weather. -1 means infinity.
    @weatherDuration = -1

    # Buffer of messages to send to each client.
    @buffer = []

    # Hash of players partaking in the battle.
    @players = {}

    # Stores last move used
    @lastMove = null

    # A queue of Pokemon ordered by priority of their moves.
    @priorityQueue = null

    # Stores the confusion recoil move as it may be different cross-generations
    @confusionMove = moves['confusion-recoil']

    for object in attributes.players
      {player, team} = object
      @players[player.id] = new Player(player, new Team(team, @numActive))

    # if replacing = true, continueTurn won't execute end of turn effects
    @replacing = false

  getPlayer: (id) =>
    @players[id]

  getTeam: (id) =>
    @getPlayer(id).team

  getTeams: =>
    teams = []
    for id, player of @players
      teams.push(player.team)
    teams

  # Returns all opponents of a given player. In a 1v1 it returns
  # an array with only one opponent.
  getOpponents: (id) =>
    opponents = []
    for playerId, player of @players
      opponents.push(player)  if id != playerId
    opponents

  # Returns all opponent pokemon of a given player.
  #
  # id - The player who's opponent's pokemon we want to retrieve
  # max (optional) - The maximum amount of pokemon per opponent.
  #
  getOpponentPokemon: (id, max=@numActive) =>
    opponents = @getOpponents(id)
    teams = (opponent.team.slice(0, max)  for opponent in opponents)
    _.flatten(teams)

  # Returns all active pokemon on the field belonging to both players.
  # Active pokemon include fainted pokemon that have not been switched out.
  getActivePokemon: =>
    pokemon = []
    for id, player of @players
      pokemon.push(player.team.getActivePokemon()...)
    pokemon

  getActiveAlivePokemon: =>
    pokemon = @getActivePokemon()
    pokemon.filter((p) -> p.isAlive())

  # Finds the Player attached to a certain Pokemon.
  getOwner: (pokemon) =>
    for id, player of @players
      return player  if pokemon in player.team.pokemon

  # Forces the owner of a Pokemon to switch.
  forceSwitch: (pokemon) =>
    player = @getOwner(pokemon)
    switches = player.team.getAlivePokemon().map((p) -> p.name)
    @requestAction(player, switches: switches)

  # Returns true if the Pokemon has yet to move.
  willMove: (pokemon) =>
    player = @getOwner(pokemon)
    (player.id of @playerActions) && @playerActions[player.id].type == 'move'

  changeMove: (pokemon, move) =>
    player = @getOwner(pokemon)
    if @playerActions[player.id]?.type == 'move'
      @playerActions[player.id].move = move

  # Associates an attachment instance with the team of `user`.
  attachToTeam: (user, attachment) =>
    player = @getOwner(user)
    player.attachToTeam(attachment)

  getTeamAttachment: (user, attachmentName) =>
    team = @getOwner(user).team
    team.getAttachment(attachmentName)

  # Add `string` to a buffer that will be sent to each client.
  message: (string) =>
    @buffer.push(string)

  clearMessages: =>
    while @buffer.length > 0
      @buffer.pop()

  # Sends to each player the battle messages that have been queued up
  # TODO: It should be sent to spectators as well
  sendMessages: =>
    for id, player of @players
      player.updateChat('SERVER', @buffer.join("<br>"))
    @clearMessages()

  # Passing -1 to turns makes the weather last forever.
  setWeather: (weatherName, turns=-1) =>
    @weather = weatherName
    @weatherDuration = turns

  hasWeather: (weatherName) =>
    weather = (if @hasWeatherCancelAbilityOnField() then Weather.NONE else @weather)
    weatherName == weather

  stopWeather: =>
    message = switch @weather
      when Weather.SUN
        "The sunlight faded."
      when Weather.RAIN
        "The rain stopped."
      when Weather.SAND
        "The sandstorm subsided."
      when Weather.HAIL
        "The hail stopped."
    @setWeather(Weather.NONE)
    message

  weatherMessage: =>
    switch @weather
      when Weather.SAND
        "The sandstorm rages."
      when Weather.HAIL
        "The hail crashes down."

  weatherUpkeep: =>
    if @weatherDuration == 1
      @stopWeather()
    else if @weatherDuration > 1
      @weatherDuration--

    message = @weatherMessage()
    @message(message)  if message?

    activePokemon = @getActivePokemon().filter((p) -> !p.isFainted())
    for pokemon in activePokemon
      damage = Math.floor(pokemon.stat('hp') / 16)
      if @hasWeather(Weather.HAIL) && !pokemon.hasType("Ice")
        @message "#{pokemon.name} is buffeted by the hail!"
        pokemon.damage(damage)
      else if @hasWeather(Weather.SAND) && !pokemon.hasType("Ground") &&
              !pokemon.hasType("Rock") && !pokemon.hasType("Steel")
        @message "#{pokemon.name} is buffeted by the sandstorm!"
        pokemon.damage(damage)

  hasWeatherCancelAbilityOnField: =>
    _.any @getActivePokemon(), (pokemon) ->
      pokemon.hasAbility('Air Lock') || pokemon.hasAbility('Cloud Nine')

  # Begins the turn. Replacements are performed and actions are requested
  # from each player. If no pokemon can move, then the battle engine
  # progresses to continueTurn. Otherwise, the battle waits for
  # user responses.
  beginTurn: =>
    @performReplacements()

    @turn++
    @priorityQueue = null

    team.beginTurn(this)  for team in @getTeams()
    pokemon.beginTurn(this) for pokemon in @getActivePokemon()

    # Send appropriate requests to players
    # TODO: If no Pokemon can move, request no actions and skip to continueTurn.
    # TODO: Struggle if no moves are usable
    for id, player of @players
      poke_moves = player.team.at(0).validMoves()
      switches = player.team.getAlivePokemon().map((p) -> p.name)
      @requestAction(player, moves: poke_moves, switches: switches)

  # Continues the turn. This is called once all requests
  # have been submitted and the battle is ready to continue.
  continueTurn: =>
    @determineTurnOrder()
    while @priorityQueue.length > 0
      {pokemon} = @priorityQueue.shift()
      {id} = @getOwner(pokemon)
      continue  if pokemon.isFainted()

      action = @popAction(id)
      switch action.type
        when 'switch' then @performSwitch(id, action.to)
        when 'move'   then @performMove(id, action.move)

      # Update Pokemon itself.
      # TODO: Is this the right place?
      pokemon.update(this)

      # If a move adds a request to the queue, the request must be resolved
      # before the battle can continue.
      if @requestQueue.length > 0
        {player, validActions} = @requestQueue.shift()
        @sendMessages()
        @requestAction(player, validActions)
        break

  # Performs end turn effects.
  endTurn: =>
    team.endTurn(this)  for team in @getTeams()
    pokemon.endTurn(this)  for pokemon in @getActiveAlivePokemon()
    @weatherUpkeep()
    @sendMessages()

  endBattle: =>
    winner = @getWinner()
    for id, player of @players
      @message "#{winner.username} won!"
      @message "END BATTLE."
    @sendMessages()

  getWinner: =>
    winner = null
    length = 0
    for id, player of @players
      newLength = player.team.getAlivePokemon().length
      if newLength > length
        length = newLength
        winner = player
    player

  isOver: =>
    _.any(@players, (player) -> player.team.getAlivePokemon().length == 0)

  # Tells the player to execute a certain move by name. The move is added
  # to the list of player actions, which are executed once the turn continues.
  # TODO: Make this compatible with double battles by using the slot.
  #
  # player - the player object that will execute the move
  # moveName - the name of the move to execute
  #
  recordMove: (playerId, move) =>
    # Store the move that this player wants to make.
    @playerActions[playerId] =
      type: 'move'
      move: move

    delete @requests[playerId]

  # Tells the player to switch with a certain pokemon specified by position.
  # The switch is added to the list of player actions, which are executed
  # once the turn continues.
  # TODO: Make this compatible with double battles by using the slot.
  #
  # player - the player object that will execute the move
  # toPosition - the index of the pokemon to switch to
  #
  recordSwitch: (playerId, toPosition) =>
    pokemon = @getTeam(playerId).at(toPosition)

    # Record the switch
    @playerActions[playerId] =
      type: 'switch'
      to: toPosition

    delete @requests[playerId]

  getAction: (clientId) =>
    @playerActions[clientId]

  popAction: (clientId) =>
    action = @getAction(clientId)
    delete @playerActions[clientId]
    action

  requestAction: (player, validActions) =>
    # TODO: Delegate this kind of logic to the Player class.
    @requests[player.id] = validActions
    player.requestAction(@id, validActions)

  # Returns true if all requests have been completed. False otherwise.
  areAllRequestsCompleted: =>
    requests = 0
    requests += 1  for id of @requests
    requests == 0

  # Returns true if any player's active Pokemon are fainted.
  areReplacementsNeeded: =>
    for id, player of @players
      if player.team.getActiveFaintedPokemon().length > 0
        return true
    return false

  # Force people to replace fainted Pokemon.
  requestFaintedReplacements: =>
    @replacing = true
    for id, player of @players
      team = player.team
      fainted = team.getActiveFaintedPokemon()
      if fainted.length > 0
        validActions = {switches: team.getAliveBenchedPokemon()}
        @requestAction(player, validActions)

  determineTurnOrder: =>
    return @priorityQueue  if @priorityQueue?
    ids = (id  for id of @playerActions)
    @priorityQueue = []
    for id in ids
      action = @getAction(id)
      priority = @actionPriority(action)
      pokemon = @getTeam(id).at(0)
      @priorityQueue.push({id, priority, pokemon})
    @priorityQueue.sort(@orderComparator)
    @priorityQueue

  orderComparator: (a, b) =>
    diff = b.priority - a.priority
    if diff == 0
      diff = b.pokemon.stat('speed') - a.pokemon.stat('speed')
      if diff == 0
        diff = (if @rng.next("turn order") < .5 then -1 else 1)
    diff

  actionPriority: (action) =>
    switch action.type
      when 'switch' then 5
      # TODO: Apply priority callbacks
      when 'move'   then action.move.priority

  # Executed by @continueTurn
  performSwitch: (id, toPosition) =>
    player = @getPlayer(id)
    team = @getTeam(id)

    team.switch(this, player, 0, toPosition)

    # TODO: Hacky.
    # TODO: Move to controller
    player.emit? 'switch pokemon', 0, toPosition

  # Executed by @beginTurn
  performReplacements: =>
    for id of @playerActions
      @performSwitch(id, @popAction(id).to)

  # Executed by @continueTurn
  performMove: (id, move) =>
    player = @getPlayer(id)
    pokemon = @getTeam(id).at(0)
    targets = @getTargets(move, id, pokemon)
    targets = targets.filter((p) -> !p.isFainted())

    @message "#{player.username}'s #{pokemon.name} used #{move.name}!"

    if pokemon.beforeMove(this, move, pokemon, targets) != false
      # TODO: Pressure
      pokemon.reducePP(move)
      damage = move.execute(this, pokemon, targets)
      # TODO: Execute any after move events

      # TODO: If move is interrupted, do we record?
      # Record last move.
      @lastMove = move
      pokemon.lastMove = move

    # TODO: Is this the right place...?
    pokemon.resetRecords()

  getTargets: (move, id, user) =>
    switch move.target
      when 'user'
        [ @getTeam(id).at(0) ]
      when 'user-or-ally'
        # TODO: Actually get selected Pokemon from client
        [ @getTeam(id).at(0) ]
      when 'all-opponents'
        @getOpponentPokemon(id, @numActive)
      when 'selected-pokemon'
        # TODO: Actually get selected Pokemon from client.
        @getOpponentPokemon(id, 1)
      when 'all-other-pokemon'
        # TODO: Add your own party Pokemon as well.
        @getOpponentPokemon(id, @numActive)
      when 'entire-field'
        @getActivePokemon()
      when 'random-opponent'
        pokemon = @getOpponentPokemon(id, @numActive)
        [ @rng.choice(pokemon) ]
      when 'users-field'
        @getTeam(id).pokemon
      when 'specific-move'
        move.getTargets(this, user)
      when 'opponents-field'
        @getOpponents(id)
      else
        throw new Error("Unimplemented target: #{move.target}.")

  getMove: (moveName) =>
    moveName = moveName.toLowerCase().replace(/\s+/g, '-')
    moves[moveName]

  toString: =>
    "[Battle id:#{@id} turn:#{@turn} weather:#{@weather}]"
