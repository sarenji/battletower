{_} = require 'underscore'
{Ability, Item, Moves, SpeciesData, FormeData} = require './data'
{Attachment, Status, Attachments} = require './attachment'
{Weather} = require './weather'
{Protocol} = require '../../shared/protocol'
Query = require './queries'
util = require './util'
floor = Math.floor

class @Pokemon
  # TODO: Take the species obj, not attributes?
  constructor: (attributes = {}) ->
    # Inject battle and team dependencies
    @battle = attributes.battle
    @team   = attributes.team
    @player = attributes.player

    @name = attributes.name || 'Missingno'
    @species = SpeciesData[@name]
    @forme = attributes.forme || "default"
    @level = attributes.level || 100
    @gender = attributes.gender || "Genderless"
    @shiny = attributes.shiny
    @nfe = (@species?.evolvesInto?.length > 0)

    @attachments = new Attachments()
    @resetForme()

    @nature = attributes.nature
    @evs = attributes.evs || {}
    @ivs = attributes.ivs || {}
    @currentHP = @stat('hp')

    @moves = (attributes.moves || []).map (move) -> Moves[move]
    @used = {}
    @resetAllPP()
    @item = Item[attributes.item?.replace(/\s+/g, '')]
    @ability = Ability[attributes.ability?.replace(/\s+/g, '')]
    @status = null

    @stages =
      attack: 0
      defense: 0
      speed: 0
      specialDefense: 0
      specialAttack: 0
      evasion: 0
      accuracy: 0

    # What moves are blocked, and is switching blocked, and is item blocked
    @resetBlocks()

    # a record of how long this pokemon has been in play.
    @turnsActive = 0

    # a record of the last move used by this pokemon.
    @lastMove = null

    # a record of the last item used by this pokemon.
    # if the item is removed by someone else, it is not recorded.
    @lastItem = null

    # a record of whether the pokemon has officially fainted or not.
    @fainted = false

  getForme: (newForme) ->
    availableFormes = FormeData[@name] || {}
    availableFormes[newForme || @forme]

  isInForme: (forme) ->
    @forme == forme

  changeForme: (newForme) ->
    return  if !@getForme(newForme)
    @changeSprite(newForme)
    @forme = newForme
    @resetForme()

  resetForme: ->
    forme      = @getForme() || {}
    @baseStats = _.clone(forme.stats) || {}
    @types     = _.clone(forme.types) || []
    @weight    = forme.weight

  changeSprite: (newSpecies, newForme) ->
    if arguments.length == 1
      [newSpecies, newForme] = [@name, newSpecies]
    @tell(Protocol.SPRITE_CHANGE, newSpecies, newForme)

  iv: (stat) -> (if stat of @ivs then @ivs[stat] else 31)
  ev: (stat) -> (if stat of @evs then @evs[stat] else 0)

  pp: (move) -> @ppHash[move.name]
  maxPP: (move) -> @maxPPHash[move.name]

  reducePP: (move, amount = 1) ->
    @setPP(move, @pp(move) - amount)

  setPP: (move, pp) ->
    pp = Math.max(pp, 0)
    pp = Math.min(pp, @maxPP(move))
    @ppHash[move.name] = pp
    @player?.tell(Protocol.CHANGE_PP, @player.index,
                  @team.pokemon.indexOf(this),
                  @moves.indexOf(move), pp)
    pp

  resetAllPP: (pp) ->
    @ppHash = {}
    @maxPPHash = {}
    if @moves?
      for move in @moves
        @ppHash[move.name] = @maxPPHash[move.name] = pp || (move.pp * 8/5)

  # Gets the stat indexed by key.
  # Ex: pokemon.stat('hp')
  # TODO: Precalculate the stats in the constructor
  stat: (key, options = {}) ->
    base = @baseStats[key] || 100
    return 1  if base == 1  # For Shedinja. key doesn't have to be hp.
    iv = @iv(key)
    ev = floor(@ev(key) / 4)
    total = if key == 'hp'
      floor((2 * base + iv + ev) * (@level / 100) + @level + 10)
    else
      floor(((2 * base + iv + ev) * (@level / 100) + 5) * @natureBoost(key))
    capitalized = key[0].toUpperCase() + key.substr(1)
    total = Query.chain("edit#{capitalized}", @attachments.all(), total)
    total = @statBoost(key, total, options)  if key != 'hp'
    total

  # Returns 1.1, 1.0, or 0.9 according to whether a Pokemon's nature corresponds
  # to that stat. The default return value is 1.0.
  natureBoost: (stat) ->
    nature = @nature?.toLowerCase()
    if nature of natures
      natures[nature][stat] || 1
    else
      1

  statBoost: (statName, total, options = {}) ->
    stages = @editBoosts()
    boost  = stages[statName]
    boost  = 0 if options.ignorePositiveBoosts && boost > 0
    boost  = 0 if options.ignoreNegativeBoosts && boost < 0
    if boost >= 0
      Math.floor((2 + boost) * total / 2)
    else
      Math.floor(2 * total / (2 - boost))

  # Boosts this pokemon's stats by the given number of stages.
  # Returns a hashmap of the stats that were boosted. The keys are the stats.
  # If no stat was boosted, the value for that stat is false.
  #
  # Example: pokemon.boost(specialAttack: 1, evasion: 2)
  #
  boost: (boosts, source = this) ->
    boosts = Query.chain('transformBoosts', @attachments.all(), _.clone(boosts), source)
    boosted = {}
    for stat, amount of boosts
      amount *= -1  if @ability == Ability.Contrary
      if stat not of @stages
        throw new Error("Tried to boost non-existent stat #{stat} by #{amount}")
      previous = @stages[stat]
      @stages[stat] += amount
      @stages[stat] = Math.max(-6, @stages[stat])
      @stages[stat] = Math.min(6, @stages[stat])
      boosted[stat] = (@stages[stat] != previous)
    if @battle then util.printBoostMessage(@battle, this, boosted, boosts)
    boosted

  positiveBoostCount: ->
    count = 0
    for stage, total of @stages
      count += total  if total > 0
    count

  resetBoosts: ->
    @stages.attack = 0
    @stages.defense = 0
    @stages.speed = 0
    @stages.specialAttack = 0
    @stages.specialDefense = 0
    @stages.accuracy = 0
    @stages.evasion = 0

  hasType: (type) ->
    type in @types

  hasAbility: (ability) ->
    return false  unless @ability
    if typeof ability == 'string'
      @ability.displayName == ability
    else
      @ability == ability

  hasItem: (itemName) ->
    if itemName?
      @item?.displayName == itemName
    else
      @item?

  hasStatus: ->
    return !!@status

  has: (attachment) ->
    @attachments.contains(attachment)

  get: (attachment) ->
    @attachments.get(attachment)

  cureStatus: (status) ->
    if !status? || Status[@status] == status
      @unattach(Status[@status])  if @status

  # TODO: really ugly copying of ability
  copyAbility: (ability) ->
    if @ability
      @get(@ability).switchOut?()
      @unattach(@ability)
    @ability = ability
    @attach(@ability).switchIn?()  if @ability

  setItem: (item) ->
    if @hasItem() then @removeItem()
    @item = item
    attachment = @attach(@item)
    attachment.switchIn?()  if !@isItemBlocked()

  getItem: ->
    @item

  useItem: ->
    item = @item
    @removeItem()
    @lastItem = item

  removeItem: ->
    return  unless @item
    @attach(Attachment.Unburden)  if @hasAbility("Unburden")
    @get(@item).switchOut?()
    @unattach(@item)
    @lastItem = null
    oldItem = @item
    @item = null
    oldItem

  hasTakeableItem: ->
    return false  if !@hasItem()
    return false  if @item.type == 'mail'
    return false  if @item.type == 'key'
    return false  if @hasAbility("Multitype") && @item.plate
    return false  if @name == 'Giratina' && @forme == 'origin'
    return false  if @name == 'Genesect' && /Drive$/.test(@item.displayName)
    true

  # This differs from hasTakeableItem by virtue of Sticky Hold
  canLoseItem: ->
    @hasTakeableItem() && !@has(Ability.StickyHold)

  isAlive: ->
    !@isFainted()

  isFainted: ->
    @currentHP <= 0

  faint: ->
    if @battle
      @battle.message "#{@name} fainted!"
      @battle.tell(Protocol.FAINT, @player.index, @battle.getSlotNumber(this))
      # Remove pending actions they had.
      @battle.popAction(this)
    @setHP(0)  if !@isFainted()
    @fainted = true
    # TODO: If a Pokemon faints in an afterFaint, should it be added to this?
    Query('afterFaint', @attachments.all())

  damage: (amount, options = {}) ->
    amount = @transformHealthChange(amount, options)
    @setHP(@currentHP - amount)

  heal: (amount) ->
    @setHP(@currentHP + amount)

  drain: (amount, source) ->
    if @hasItem("Big Root") && !@isItemBlocked()
      amount = util.roundHalfDown(amount * 1.3)
    amount *= -1  if source != this && source?.hasAbility("Liquid Ooze")
    @heal(amount)

  transformHealthChange: (damage, options) ->
    Query.chain('transformHealthChange', @attachments.all(), damage, options)

  editPriority: (priority, move) ->
    Query.chain('editPriority', @attachments.all(), priority, move)

  editDamage: (move, damage) ->
    Query.chain('editDamage', @attachments.all(), damage, move, this)

  editBoosts: ->
    Query.chain('editBoosts', @attachments.all(), _.clone(@stages))

  editAccuracy: (accuracy, move, target) ->
    Query.chain('editAccuracy', @attachments.all(), accuracy, move, target)

  editEvasion: (accuracy, move, user) ->
    Query.chain('editEvasion', @attachments.all(), accuracy, move, user)

  editMoveType: (type, target) ->
    Query.chain('editMoveType', @attachments.all(), type, target)

  calculateWeight: ->
    Query.chain('calculateWeight', @attachments.all(), @weight)

  criticalModifier: ->
    Query.chain('criticalModifier', @attachments.all(), 0)

  setHP: (hp) ->
    oldHP = @currentHP
    @currentHP = Math.min(@stat('hp'), hp)
    @currentHP = Math.max(@currentHP, 0)
    delta = oldHP - @currentHP
    if delta != 0
      pixels = Math.floor(48 * @currentHP / @stat('hp'))
      pixels = 1  if pixels == 0 && @isAlive()
      @battle?.tell(Protocol.CHANGE_HP, @player.index, @team.indexOf(this), pixels)
      @player?.tell(Protocol.CHANGE_EXACT_HP, @player.index, @team.indexOf(this), @currentHP)
    delta

  recordMove: (move) ->
    @lastMove = move
    @used[move.name] = true

  recordHit: (pokemon, damage, move, turn) ->
    @lastHitBy = {pokemon, damage, move, turn}

  isImmune: (type, move) ->
    b = Query.untilNotNull('isImmune', @attachments.all(), type, move)
    if b? then return b

    return false  if move?.ignoresImmunities()

    multiplier = util.typeEffectiveness(type, @types)
    return multiplier == 0

  isWeatherDamageImmune: (weather) ->
    b = Query.untilNotNull('isWeatherDamageImmune', @attachments.all(), weather)
    if b? then return b

    return true  if weather == Weather.HAIL && @hasType("Ice")
    return true  if weather == Weather.SAND && (@hasType("Ground") ||
                     @hasType("Rock") || @hasType("Steel"))
    return @battle?.hasWeatherCancelAbilityOnField() || false

  switchIn: ->
    @turnsActive = 0
    @attach(@ability)  if @ability
    @attach(@item)   if @item
    Query('switchIn', @attachments.all())

  switchOut: ->
    delete @lastMove
    @used = {}
    Query('switchOut', @attachments.all())
    @attachments.unattachAll((a) -> a.volatile)
    @resetForme()
    @resetBoosts()
    @resetBlocks()

  informSwitch: (switcher) ->
    Query('informSwitch', @attachments.all(), switcher)

  shouldPhase: (phaser) ->
    Query.untilFalse('shouldPhase', @attachments.all(), phaser) != false

  informCriticalHit: ->
    Query('informCriticalHit', @attachments.all())

  informWeather: (weather) ->
    Query('informWeather', @attachments.all(), weather)

  beginTurn: ->
    Query('beginTurn', @attachments.all())

  beforeMove: (move, user, targets) ->
    Query.untilFalse('beforeMove', @attachments.all(), move, user, targets)

  afterMove: (move, user, targets) ->
    Query('afterMove', @attachments.all(), move, user, targets)

  shouldBlockExecution: (move, user) ->
    Query.untilTrue('shouldBlockExecution', @attachments.all(), move, user)

  update: ->
    Query('update', @attachments.all())

  afterTurnOrder: ->
    Query('afterTurnOrder', @attachments.all())

  calculateNumberOfHits: (move, targets) ->
    Query.untilNotNull("calculateNumberOfHits", @attachments.all(), move, targets)

  resetRecords: ->
    @lastHitBy = null

  # Hook for when the Pokemon gets hit by a move
  afterBeingHit: (move, user, target, damage) ->
    Query('afterBeingHit', @attachments.all(), move, user, target, damage)

  afterSuccessfulHit: (move, user, target, damage) ->
    Query('afterSuccessfulHit', @attachments.all(), move, user, target, damage)

  # Adds an attachment to the list of attachments
  attach: (attachment, options={}) ->
    options = _.clone(options)
    @attachments.push(attachment, options, battle: @battle, team: @team, pokemon: this)

  # Removes an attachment from the list of attachment
  unattach: (klass) ->
    # TODO: Do we need to remove circular dependencies?
    # Removing them here will result in some unanticipated consequenes.
    @attachments.unattach(klass)

  # Blocks a move for a single turn
  blockMove: (move) ->
    @blockedMoves.push(move)

  # Blocks all moves for a single turn
  blockMoves: ->
    @blockMove(move)  for move in @moves

  isMoveBlocked: (move) ->
    return (move in @blockedMoves)

  isSwitchBlocked: ->
    @switchBlocked

  # Returns true if the Pokemon has no item or the item has been blocked.
  isItemBlocked: ->
    !@item? || @itemBlocked

  # Blocks a switch for a single turn
  blockSwitch: ->
    @switchBlocked = true  unless !@isItemBlocked() && @hasItem("Shed Shell")

  # Blocks an item for a single turn
  blockItem: ->
    @itemBlocked = true

  resetBlocks: ->
    @blockedMoves = []
    @switchBlocked = false
    @itemBlocked = false

  # Locks the Pokemon into a single move. Does not limit switches.
  lockMove: (moveToLock) ->
    for move in @validMoves()
      @blockMove(move)  if move != moveToLock

  tell: (protocol, args...) ->
    return  unless @battle
    args = [ @player.index, @team.indexOf(this), args... ]
    @battle.tell(protocol, args...)

  # Returns whether this Pokemon has this move in its moveset.
  knows: (move) ->
    move in @moves

  # A list of moves that this pokemon can use freely
  validMoves: ->
    moves = _(@moves).difference(@blockedMoves)
    moves = moves.filter((move) => @pp(move) > 0)
    moves

  toString: ->
    "[Pokemon name:#{@name} hp:#{@currentHP}/#{@stat('hp')}]"

  toJSON: (options = {}) ->
    base =
      "name"      : @name
      "level"     : @level
      "gender"    : @gender
      "boosts"    : @stages
      "forme"     : @forme
      "shiny"     : @shiny == true
    return base  if options.hidden
    base = Object.merge base,
      "hp"        : @currentHP
      "maxHP"     : @stat('hp')
      "moves"     : @moves.map (m) -> m.name
      "moveTypes" : @moves.map (m) -> m.type
      "pp"        : @moves.map (m) => @pp(m)
      "maxPP"     : @moves.map (m) => @maxPP(m)
      "ivs"       :
        hp: @iv('hp')
        attack: @iv('attack')
        defense: @iv('defense')
        speed: @iv('speed')
        specialAttack: @iv('specialAttack')
        specialDefense: @iv('specialDefense')
    base["item"] = @item.displayName  if @item
    base["ability"] = @ability.displayName  if @ability
    base

# A hash that keys a nature with the stats that it boosts.
# Neutral natures are ignored.
# TODO: .yml-ify these.
PLUS  = 1.1
MINUS = 0.9
natures =
  lonely:  {attack: PLUS, defense: MINUS}
  brave:   {attack: PLUS, speed: MINUS}
  adamant: {attack: PLUS, specialAttack: MINUS}
  naughty: {attack: PLUS, specialDefense: MINUS}
  bold:    {defense: PLUS, attack: MINUS}
  relaxed: {defense: PLUS, speed: MINUS}
  impish:  {defense: PLUS, specialAttack: MINUS}
  lax:     {defense: PLUS, specialDefense: MINUS}
  timid:   {speed: PLUS, attack: MINUS}
  hasty:   {speed: PLUS, defense: MINUS}
  jolly:   {speed: PLUS, specialAttack: MINUS}
  naive:   {speed: PLUS, specialDefense: MINUS}
  modest:  {specialAttack: PLUS, attack: MINUS}
  mild:    {specialAttack: PLUS, defense: MINUS}
  quiet:   {specialAttack: PLUS, speed: MINUS}
  rash:    {specialAttack: PLUS, specialDefense: MINUS}
  calm:    {specialDefense: PLUS, attack: MINUS}
  gentle:  {specialDefense: PLUS, defense: MINUS}
  sassy:   {specialDefense: PLUS, speed: MINUS}
  careful: {specialDefense: PLUS, specialAttack: MINUS}

