{Weather} = require '../../../shared/weather'

# Retcon weather abilities to only last 5 turns.
makeWeatherAbility = (name, weather) ->
  makeAbility name, ->
    this::switchIn = ->
      return  if @battle.hasWeather(weather)
      moveName = switch weather
        when Weather.SUN  then "Sunny Day"
        when Weather.RAIN then "Rain Dance"
        when Weather.SAND then "Sandstorm"
        when Weather.HAIL then "Hail"
        else throw new Error("#{weather} ability not supported.")

      @pokemon.activateAbility()
      move = @battle.getMove(moveName)
      move.changeWeather(@battle, @pokemon)

# Import old abilities

coffee = require 'coffee-script'
path = require('path').resolve(__dirname, '../../bw/data/abilities.coffee')
eval(coffee.compile(require('fs').readFileSync(path, 'utf8'), bare: true))

# Retcon old abilities

# Overcoat now also prevents powder moves from working.
Ability.Overcoat::shouldBlockExecution = (move, user) ->
    if move.hasFlag("powder")
      @pokemon.activateAbility()
      return true

# New ability interfaces

makeNormalTypeChangeAbility = (name, newType) ->
  makeAbility name, ->
    this::editMoveType = (type, target) ->
      return newType  if type == 'Normal' && @pokemon != target
      return type

    this::modifyBasePower = (move, target) ->
      return 0x14CD  if move.type == 'Normal'
      return 0x1000

makeNormalTypeChangeAbility("Aerilate", "Flying")
makeNormalTypeChangeAbility("Pixilate", "Fairy")
makeNormalTypeChangeAbility("Refrigerate", "Ice")

makeAuraAbility = (name, type) ->
  makeAbility name, ->
    this::modifyBasePower = (move, target) ->
      return 0x1000  if move.getType(@battle, @pokemon, target) != type
      for pokemon in @battle.getActiveAlivePokemon()
        return 0xC00  if pokemon.hasAbility("Aura Break")
      return 0x1547

makeAuraAbility("Dark Aura", "Dark")
makeAuraAbility("Fairy Aura", "Fairy")

# New unique abilities

# TODO: Aroma Veil
makeAbility "Aroma Veil"

# Implemented in makeAuraAbility
makeAbility "Aura Break"

makeAbility 'Bulletproof', ->
  this::isImmune = (type, move) ->
    if move?.hasFlag('bullet')
      @pokemon.activateAbility()
      return true

# TODO: Cheek Pouch
makeAbility "Cheek Pouch"

makeAbility "Competitive", ->
  this::afterEachBoost = (boostAmount, source) ->
    return  if source.team == @pokemon.team
    @pokemon.activateAbility()
    @pokemon.boost(specialAttack: 2)  if boostAmount < 0

# TODO: Flower Veil
makeAbility "Flower Veil"

makeAbility "Fur Coat", ->
  this::modifyBasePowerTarget = (move) ->
    if move.isPhysical() then 0x800 else 0x1000

makeAbility 'Gale Wings', ->
  this::editPriority = (priority, move) ->
    # TODO: Test if Gale Wings works with Hidden Power Flying.
    return priority + 1  if move.type == 'Flying'
    return priority

makeAbility "Gooey", ->
  this::isAliveCheck = -> true

  this::afterBeingHit = (move, user) ->
    if move.hasFlag("contact")
      user.boost(speed: -1, @pokemon)
      @pokemon.activateAbility()

# TODO: Grass Pelt
makeAbility "Grass Pelt"

# TODO: Magician
makeAbility "Magician"

makeAbility 'Mega Launcher', ->
  this::modifyBasePower = (move, target) ->
    return 0x1800  if move.hasFlag("pulse")
    return 0x1000

makeAbility 'Parental Bond', ->
  this::calculateNumberOfHits = (move, targets) ->
    # Do nothing if this move is multi-hit, has multiple targets, or is status.
    return  if move.minHits != 1 || targets.length > 1 || move.isNonDamaging()
    return 2

  this::modifyDamage = (move, target, hitNumber) ->
    return 0x800  if hitNumber == 2 && move.maxHits == 1
    return 0x1000

makeAbility 'Protean', ->
  this::beforeMove = (move, user, targets) ->
    type = move.getType(@battle, user, targets[0])
    return  if user.types.length == 1 && user.types[0] == type
    user.types = [ type ]
    @pokemon.activateAbility()
    @battle.message "#{user.name} transformed into the #{type} type!"

makeAbility 'Stance Change', ->
  this::beforeMove = (move, user, targets) ->
    newForme = switch
      when !move.isNonDamaging() then "blade"
      when move == @battle.getMove("King's Shield") then "default"
    if newForme && !@pokemon.isInForme(newForme) && @pokemon.name == 'Aegislash'
      @pokemon.activateAbility()
      @pokemon.changeForme(newForme)
      humanized = (if newForme == "blade" then "Blade" else "Shield")
      @battle.message("Changed to #{humanized} Forme!")
    true

makeAbility "Strong Jaw", ->
  this::modifyBasePower = (move) ->
    return 0x1800  if move.hasFlag("bite")
    return 0x1000

# TODO: Sweet Veil (2v2)
makeAttachmentImmuneAbility "Sweet Veil", [Status.Sleep]

# TODO: Symbiosis
makeAbility "Symbiosis"

makeAbility "Tough Claws", ->
  this::modifyBasePower = (move) ->
    return 0x14CD  if move.hasFlag("contact")
    return 0x1000
