# Abstracts out sending messages from player to battle.
# Makes the Battle smoothly go into the next turn
# Necessary to separate out making commands and executing commands.
class @BattleController
  constructor: (@battle) ->

  # Officially starts the battle.
  beginBattle: =>
    pokemon = @battle.getActivePokemon()
    for p in pokemon
      p.switchIn(@battle)

    @beginTurn()

  # Tells the player to execute a certain move by name. The move is added
  # to the list of player actions, which are executed once the turn continues.
  makeMove: (player, moveName) =>
    move = @battle.getMove(moveName)
    # TODO: Fail if move not in moves
    # TODO: Fail if move not in player pokemon's moves
    return  if !move?
    @battle.recordMove(player.id, move)

    # Automatically continue the turn if each player has moved.
    @continueTurn()  if @battle.areAllRequestsCompleted()

  # Tells the player to switch with a certain pokemon specified by position.
  # The switch is added to the list of player actions, which are executed
  # once the turn continues.
  makeSwitch: (player, toPosition) =>
    # TODO: Send error messages back on invalid indices (such as fainted poke
    #       or activePokemon)
    @battle.recordSwitch(player.id, toPosition)

    # Continue or begin a new turn if each player has made an action.
    if @battle.areAllRequestsCompleted()
      if @battle.replacing
        @beginTurn()
      else
        @continueTurn()

  # An alternate version of #makeSwitch which takes the name of a pokemon
  # to switch to instead of the position. Useful for tests.
  # TODO: Test
  makeSwitchByName: (player, toPokemon) =>
    team = @battle.getTeam(player.id)
    index = team.pokemon.map((p) -> p.name).indexOf(toPokemon)

    @makeSwitch(player, index)

  beginTurn: =>
    @battle.beginTurn()

  # Continues the turn. This is called once all requests
  # have been submitted and the battle is ready to continue.
  #
  # If there are no more requests, the engine progresses to endTurn. Otherwise,
  # it waits for continueTurn to be called again.
  continueTurn: =>
    @battle.continueTurn()

    # If all requests have been completed, then end the turn.
    # Otherwise, wait for further requests to be completed before ending.
    if @battle.areAllRequestsCompleted() then @endTurn()

  # Calls Battle#endTurn. If all pokemon are fainted, then it
  # ends the battle. Otherwise, it will request for new pokemon and wait if
  # any replacements are needed, or begins the next turn.
  endTurn: =>
    @battle.endTurn()

    if @battle.areReplacementsNeeded()
      if !@battle.isOver()
        @battle.requestFaintedReplacements()
      else
        @endBattle()
    else
      @beginTurn()

  endBattle: =>
    @battle.endBattle()
