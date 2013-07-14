{_} = require 'underscore'
{Ability, Items, Moves} = require '../data/bw'
{Status, StatusAttachment} = require './status'
{Attachment, Attachments} = require './attachment'
{Weather} = require './weather'
util = require './util'
floor = Math.floor

class @Pokemon
  # TODO: Take the species obj, not attributes?
  constructor: (attributes = {}) ->
    @name = attributes.name || 'Missingno'
    @species = attributes.species
    @level = attributes.level || 100
    @baseStats = attributes.stats || {}
    @weight = attributes.weight  # in kg
    @gender = attributes.gender || "Genderless"
    @attachments = new Attachments()

    @nature = attributes.nature
    @evs = attributes.evs || {}
    @ivs = attributes.ivs || {}
    @currentHP = @stat('hp')

    @moves = attributes.moves?.map (move) ->
      Moves[move.toLowerCase().replace(/\s+/g, '-')]
    @used = {}
    @resetAllPP()
    @types = attributes.types || [] # TODO: Get from species.
    @item = Items[attributes.item]
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

  resetAllPP: (pp) ->
    @ppHash = {}
    @maxPPHash = {}
    if @moves?
      for move in @moves
        @ppHash[move.name] = @maxPPHash[move.name] = pp || (move.pp * 8/5)

  # Gets the stat indexed by key.
  # Ex: pokemon.stat('hp')
  # TODO: Precalculate the stats in the constructor
  stat: (key) ->
    base = @baseStats[key] || 100
    return 1  if base == 1  # For Shedinja. key doesn't have to be hp.
    iv = @iv(key)
    ev = floor(@ev(key) / 4)
    total = if key == 'hp'
      floor((2 * base + iv + ev) * (@level / 100) + @level + 10)
    else
      floor(((2 * base + iv + ev) * (@level / 100) + 5) * @natureBoost(key))
    capitalized = key[0].toUpperCase() + key.substr(1)
    total = @item["edit#{capitalized}"]?(total, this) || total  if !@isItemBlocked()
    total = @attachments.queryChain("edit#{capitalized}", total)
    total = @statBoost(key, total)  if key != 'hp'
    total

  # Returns 1.1, 1.0, or 0.9 according to whether a Pokemon's nature corresponds
  # to that stat. The default return value is 1.0.
  natureBoost: (stat) ->
    nature = @nature?.toLowerCase()
    if nature of natures
      natures[nature][stat] || 1
    else
      1

  statBoost: (statName, total) ->
    stages = @editBoosts()
    boost  = stages[statName]
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
  boost: (boosts) ->
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
      @ability::name == ability
    else
      @ability == ability

  hasItem: (itemName) ->
    if itemName?
      @item?.name == itemName
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
  copyAbility: (battle, ability) ->
    if @ability
      @get(@ability).switchOut(battle)
      @unattach(@ability)
    @ability = ability
    @attach(@ability).switchIn(battle)  if @ability

  setItem: (battle, item) ->
    if @hasItem() then @removeItem()
    @item = item
    @item.initialize(battle, this)

  getItem: ->
    @item

  removeItem: ->
    @item.deactivate(this)
    @item = null

  hasTakeableItem: ->
    return false  if !@item?
    return false  if @item.type == 'mail'
    return false  if @item.type == 'key'
    return false  if @hasAbility("Sticky Hold")
    return false  if @hasAbility("Multitype") && @item.plate?
    return false  if @name == 'Giratina (origin)'
    return false  if @name == 'Genesect' && /Drive$/.test(@item.name)
    true

  isAlive: ->
    !@isFainted()

  isFainted: ->
    @currentHP <= 0

  faint: ->
    @currentHP = 0

  afterFaint: (battle) ->
    @attachments.query('afterFaint', battle)

  damage: (amount) ->
    @setHP(@currentHP - amount)
    amount

  drain: (amount, source) ->
    if @hasItem("Big Root") && !@isItemBlocked()
      amount = util.roundHalfDown(amount * 1.3)
    amount *= -1  if source != this && source?.hasAbility("Liquid Ooze")
    @damage(-amount)

  transformHealthChange: (damage) ->
    damage = @attachments.queryChain('transformHealthChange', damage)
    damage

  editDamage: (battle, move, damage) ->
    damage = @attachments.queryChain('editDamage', damage, battle, move, this)
    damage = @item.editDamage(battle, this, move, damage)  if !@isItemBlocked()
    damage

  editBoosts: ->
    stages = _.clone(@stages)
    stages = @attachments.queryChain('editBoosts', stages)
    stages

  editAccuracy: (accuracy, move) ->
    accuracy = @item.editAccuracy?(accuracy, move) || accuracy  if !@isItemBlocked()
    accuracy = @attachments.queryChain('editAccuracy', accuracy, move)
    accuracy

  editEvasion: (accuracy, move) ->
    accuracy = @attachments.queryChain('editEvasion', accuracy, move)
    accuracy

  setHP: (hp) ->
    @currentHP = Math.min(@stat('hp'), hp)

  recordMove: (move) ->
    @lastMove = move
    @used[move.name] = true

  recordHit: (pokemon, damage, move, turn) ->
    @lastHitBy = {pokemon, damage, move, turn}

  isImmune: (battle, type) ->
    b = @attachments.queryUntilNotNull('isImmune', battle, type)
    if b? then return b

    multiplier = util.typeEffectiveness(type, @types)
    return multiplier == 0

  isWeatherDamageImmune: (battle, weather) ->
    b = @attachments.queryUntilNotNull('isWeatherDamageImmune', battle, weather)
    if b? then return b

    return true  if weather == Weather.HAIL && @hasType("Ice")
    return true  if weather == Weather.SAND && (@hasType("Ground") ||
                     @hasType("Rock") || @hasType("Steel"))
    return battle?.hasWeatherCancelAbilityOnField() || false

  calculateWeight: ->
    weight = @weight
    weight = @item.calculateWeight(weight)  if !@isItemBlocked()
    weight = @attachments.queryChain('calculateWeight', weight)
    weight

  switchIn: (battle) ->
    @turnsActive = 0
    @attach(@ability).switchIn(battle)  if @ability
    @item.initialize(battle, this)  if !@isItemBlocked()

  switchOut: (battle) ->
    @resetBoosts()
    @resetBlocks()
    delete @lastMove
    @used = {}
    if @ability
      @get(@ability).switchOut(battle)
      @unattach(@ability)
    @attachments.query('switchOut', battle)
    @attachments.unattachAll((a) -> a.volatile)

  informSwitch: (battle, switcher) ->
    @attachments.query('informSwitch', battle, switcher)

  informPhase: (battle, phaser) ->
    @attachments.queryUntilFalse('informPhase', battle, phaser) != false

  informCriticalHit: (battle) ->
    @attachments.query('informCriticalHit', battle)

  informWeather: (weather) ->
    @attachments.query('informWeather', weather)

  beginTurn: (battle) ->
    @attachments.query('beginTurn', battle)

  afterTurnOrder: (battle) ->
    @item.afterTurnOrder(battle, this)  if !@isItemBlocked()

  beforeMove: (battle, move, user, targets) ->
    @attachments.queryUntilFalse('beforeMove', battle, move, user, targets)

  afterMove: (battle, move, user, targets) ->
    @attachments.query('afterMove', battle, move, user, targets)

  shouldBlockExecution: (battle, move, user) ->
    @attachments.queryUntilTrue('shouldBlockExecution', battle, move, user)

  update: (battle) ->
    @item.update(battle, this)  if !@isItemBlocked()
    @attachments.query('update', battle, this)

  resetRecords: ->
    @lastHitBy = null

  # Hook for when the Pokemon gets hit by a move
  afterBeingHit: (battle, move, user, target, damage) ->
    @item.afterBeingHit(battle, move, user, target, damage)  if !@isItemBlocked()
    @attachments.query('afterBeingHit', battle, move, user, target, damage)

  afterSuccessfulHit: (battle, move, user, target, damage) ->
    @item.afterSuccessfulHit(battle, move, user, target, damage)  if !@isItemBlocked()
    @attachments.query('afterSuccessfulHit', battle, move, user, target, damage)

  endTurn: (battle) ->
    @item.endTurn(battle, this)  if !@isItemBlocked()
    @attachments.query('endTurn', battle)
    @turnsActive += 1

  # Adds an attachment to the list of attachments
  attach: (attachment, options={}) ->
    options = _.clone(options)
    @attachments.push(attachment, options, pokemon: this)

  # Removes an attachment from the list of attachment
  unattach: (klass) ->
    attachment = @attachments.unattach(klass)
    delete attachment.pokemon  if attachment?
    attachment

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

  # Returns whether this Pokemon has this move in its moveset.
  knows: (move) ->
    move in @moves

  # A list of moves that this pokemon can use freely
  validMoves: ->
    _(@moves).difference(@blockedMoves)

  toString: ->
    "[Pokemon name:#{@name} hp:#{@currentHP}/#{@stat('hp')}]"


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

