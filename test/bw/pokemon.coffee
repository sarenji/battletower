{Battle} = require('../../server/bw/battle')
{Weather} = require('../../server/bw/weather')
{Pokemon} = require('../../server/bw/pokemon')
{Status, Attachment, BaseAttachment, VolatileAttachment} = require('../../server/bw/attachment')
{Moves, SpeciesData} = require('../../server/bw/data')
{Protocol} = require '../../shared/protocol'
should = require 'should'

require '../helpers'

describe 'Pokemon', ->
  it 'should have a name of Missingno by default', ->
    new Pokemon().name.should.equal 'Missingno'

  it 'can change the default name', ->
    new Pokemon(name: 'Pikachu').name.should.equal 'Pikachu'

  it 'should have a level of 100 by default', ->
    new Pokemon().level.should.equal 100

  it 'can change the default level', ->
    new Pokemon(level: 5).level.should.equal 5

  it 'gets its current hp populated from its max hp', ->
    new Pokemon().currentHP.should.equal 341

  it 'has pp for each move', ->
    pokemon = new Pokemon(moves: ["Tackle", "Splash"])
    pokemon.pp(Moves['Tackle']).should.equal 35 * 8/5
    pokemon.pp(Moves['Splash']).should.equal 40 * 8/5

  describe '#iv', ->
    it 'has default iv of 31', ->
      new Pokemon().iv('hp').should.equal 31

    it 'retrieves iv successfully', ->
      new Pokemon(ivs: {'hp': 25}).iv('hp').should.equal 25

    it "doesn't default to 31 if iv is 0", ->
      new Pokemon(ivs: {'hp': 0}).iv('hp').should.equal 0

  describe '#ev', ->
    it 'has default ev of 0', ->
      new Pokemon().ev('hp').should.equal 0

    it 'retrieves ev successfully', ->
      new Pokemon(evs: {hp: 25}).ev('hp').should.equal 25

  describe '#stat', ->
    it 'calculates hp correctly', ->
      pokemon = new Pokemon(level: 100, evs: { hp: 255 })
      pokemon.stat('hp').should.equal 404
      pokemon = new Pokemon(level: 50, evs: { hp: 255 })
      pokemon.stat('hp').should.equal 207
      # todo: test other numbers later

    it 'calculates 1 base HP correctly', ->
      pokemon = new Pokemon(level: 100, evs: { hp: 255 })
      pokemon.baseStats.hp = 1
      pokemon.stat('hp').should.equal 1

    it 'calculates other stats correctly', ->
      pokemon = new Pokemon(level: 100, evs: { attack: 255 })
      pokemon.stat('attack').should.equal 299
      pokemon = new Pokemon(level: 50, evs: { attack: 255 })
      pokemon.stat('attack').should.equal 152
      # todo: test other numbers later

    it "calculates a stat with a nature boost correctly", ->
      pokemon = new Pokemon(nature: 'Adamant')
      pokemon.stat('attack').should.equal 259

    it "calculates a stat with a nature decrease correctly", ->
      pokemon = new Pokemon(nature: 'Bold')
      pokemon.stat('attack').should.equal 212

  describe 'stat boosts', ->
    it 'increase the stat by (n+2)/2 if positive', ->
      pokemon = new Pokemon()
      speed = pokemon.stat('speed')
      pokemon.stages.speed = 3
      pokemon.stat('speed').should.equal Math.floor(2.5 * speed)

    it 'decrease the stat by 2/(n+2) if negative', ->
      pokemon = new Pokemon()
      speed = pokemon.stat('speed')
      pokemon.stages.speed = -3
      pokemon.stat('speed').should.equal Math.floor(speed / 2.5)

  describe '#natureBoost', ->
    it "returns 1 by default for non-existent natures", ->
      new Pokemon(nature: 'Super').natureBoost('attack').should.equal 1

    it "returns 1.1 for natures that boost a certain stat", ->
      new Pokemon(nature: 'Adamant').natureBoost('attack').should.equal 1.1

    it "returns 1.0 for natures do not affect a certain stat", ->
      new Pokemon(nature: 'Adamant').natureBoost('speed').should.equal 1

    it "returns 0.9 for natures that decrease a certain stat", ->
      new Pokemon(nature: 'Timid').natureBoost('attack').should.equal 0.9

  describe '#hasType', ->
    it 'returns false if the pokemon does not have that type', ->
      new Pokemon().hasType('Grass').should.be.false

    it 'returns true if the pokemon has that type', ->
      pokemon = new Pokemon()
      pokemon.types = ['Dark', 'Grass']
      pokemon.hasType('Grass').should.be.true

  describe '#switchOut', ->
    it 'resets stat boosts', ->
      pokemon = new Pokemon()
      pokemon.boost(specialAttack: 2)
      pokemon.switchOut()
      pokemon.stages['specialAttack'].should.equal 0

    it 'removes blocked moves', ->
      pokemon = new Pokemon(moves: ['Earthquake'])
      pokemon.blockMove(Moves['Earthquake'])
      pokemon.switchOut()
      pokemon.isMoveBlocked(Moves['Earthquake']).should.be.false

    it 'removes volatile attachments', ->
      pokemon = new Pokemon()
      pokemon.attach(VolatileAttachment)
      pokemon.switchOut()
      pokemon.has(VolatileAttachment).should.be.false

  describe '#endTurn', ->
    it 'removes blocked moves', ->
      pokemon = new Pokemon(moves: ['Earthquake'])
      pokemon.blockMove(Moves['Earthquake'])
      pokemon.switchOut()
      pokemon.isMoveBlocked(Moves['Earthquake']).should.be.false

  describe '#attach', ->
    it 'adds an attachment to a list of attachments', ->
      pokemon = new Pokemon()
      pokemon.attach(BaseAttachment)
      pokemon.has(BaseAttachment).should.be.true

  describe '#unattach', ->
    it 'removes an attachment from the list of attachments', ->
      pokemon = new Pokemon()
      pokemon.attach(BaseAttachment)
      pokemon.unattach(BaseAttachment)
      pokemon.has(BaseAttachment).should.be.false

  describe '#blockMove', ->
    it 'adds a move to a list of blocked moves', ->
      pokemon = new Pokemon(moves: ['Earthquake'])
      pokemon.blockMove(Moves['Earthquake'])
      pokemon.blockedMoves.should.include Moves['Earthquake']

  describe '#isMoveBlocked', ->
    it 'returns true if the move is blocked', ->
      pokemon = new Pokemon(moves: ['Earthquake'])
      pokemon.blockMove(Moves['Earthquake'])
      pokemon.isMoveBlocked(Moves['Earthquake']).should.be.true

    it 'returns false if the move is not blocked', ->
      pokemon = new Pokemon(moves: ['Earthquake'])
      pokemon.isMoveBlocked(Moves['Earthquake']).should.be.false

  describe '#validMoves', ->
    it 'returns moves without blocked moves', ->
      pokemon = new Pokemon(moves: ['Splash', 'Earthquake'])
      pokemon.blockMove(Moves['Earthquake'])
      pokemon.validMoves().should.eql([ Moves['Splash'] ])

    it 'excludes moves with 0 PP', ->
      pokemon = new Pokemon(moves: ['Splash', 'Earthquake'])
      move = pokemon.moves[0]
      otherMoves = pokemon.moves.filter((m) -> m != move)
      pokemon.setPP(move, 0)
      pokemon.validMoves().should.eql(otherMoves)

  describe '#reducePP', ->
    it 'reduces PP of a move by 1', ->
      pokemon = new Pokemon(moves: ['Splash', 'Earthquake'])
      move = Moves['Splash']
      pokemon.reducePP(move)
      pokemon.pp(move).should.equal pokemon.maxPP(move) - 1

    it 'does not go below 0', ->
      pokemon = new Pokemon(moves: ['Splash', 'Earthquake'])
      move = Moves['Splash']
      for x in [0..pokemon.maxPP(move)]
        pokemon.reducePP(move)
      pokemon.pp(move).should.equal 0

  describe '#setPP', ->
    it "sets the PP of a move", ->
      pokemon = new Pokemon(moves: ['Splash', 'Earthquake'])
      move = Moves['Splash']
      pokemon.setPP(move, 1)
      pokemon.pp(move).should.equal 1

    it "cannot go below 0", ->
      pokemon = new Pokemon(moves: ['Splash', 'Earthquake'])
      move = Moves['Splash']
      pokemon.setPP(move, -1)
      pokemon.pp(move).should.equal 0

    it "cannot go above the max PP possible", ->
      pokemon = new Pokemon(moves: ['Splash', 'Earthquake'])
      move = Moves['Splash']
      pokemon.setPP(move, pokemon.maxPP(move) + 1)
      pokemon.pp(move).should.equal pokemon.maxPP(move)

  describe '#positiveBoostCount', ->
    it "returns the number of boosts higher than 0", ->
      pokemon = new Pokemon()
      pokemon.boost(attack: 4, defense: -3, speed: 1)
      pokemon.positiveBoostCount().should.equal 5

  describe '#isItemBlocked', ->
    it 'returns true if the Pokemon has no item', ->
      pokemon = new Pokemon()
      pokemon.isItemBlocked().should.be.true

  describe "attaching statuses", ->
    it "returns null if attaching too many statuses", ->
      pokemon = new Pokemon()
      pokemon.attach(Status.Freeze)
      should.not.exist pokemon.attach(Status.Paralyze)

    it "does not override statuses", ->
      pokemon = new Pokemon()
      pokemon.attach(Status.Freeze)
      pokemon.attach(Status.Paralyze)
      pokemon.has(Status.Freeze).should.be.true
      pokemon.has(Status.Paralyze).should.be.false

    it "sets the status of the pokemon", ->
      for name, status of Status
        pokemon = new Pokemon()
        pokemon.attach(status)
        pokemon.status.should.equal(status.name)

    it "sets the corresponding attachment on the pokemon", ->
      for name, status of Status
        pokemon = new Pokemon()
        pokemon.attach(status)
        pokemon.has(status).should.be.true

    it "doesn't poison Poison types", ->
      pokemon = new Pokemon()
      pokemon.types = ["Poison"]
      pokemon.attach(Status.Poison)
      pokemon.attach(Status.Toxic)
      pokemon.has(Status.Poison).should.be.false
      pokemon.has(Status.Toxic).should.be.false

    it "doesn't poison Steel types", ->
      pokemon = new Pokemon()
      pokemon.types = ["Steel"]
      pokemon.attach(Status.Poison)
      pokemon.attach(Status.Toxic)
      pokemon.has(Status.Poison).should.be.false
      pokemon.has(Status.Toxic).should.be.false

    it "doesn't burn Fire types", ->
      pokemon = new Pokemon()
      pokemon.types = ["Fire"]
      pokemon.attach(Status.Burn)
      pokemon.has(Status.Burn).should.be.false

    it "doesn't freeze Ice types", ->
      pokemon = new Pokemon()
      pokemon.types = ["Ice"]
      pokemon.attach(Status.Freeze)
      pokemon.has(Status.Freeze).should.be.false

    it "doesn't freeze under Sun", ->
      battle = new Battle('id', players: [{player: {id: "a", send: ->}, team: []}
                                        , {player: {id: "b", send: ->}, team: [] }])
      battle.setWeather(Weather.SUN)
      pokemon = new Pokemon(battle: battle)
      pokemon.attach(Status.Freeze)
      pokemon.has(Status.Freeze).should.be.false

  describe "#cureStatus", ->
    it "removes all statuses if no argument is passed", ->
      pokemon = new Pokemon()
      for name, status of Status
        pokemon.attach(status)
        pokemon.cureStatus()
        pokemon.hasStatus().should.be.false

    it "removes only a certain status if an argument is passed", ->
      pokemon = new Pokemon()
      pokemon.attach(Status.Freeze)
      pokemon.cureStatus(Status.Paralyze)
      pokemon.has(Status.Freeze).should.be.true

  describe '#hasTakeableItem', ->
    it "returns false if the pokemon has no item", ->
      pokemon = new Pokemon()
      pokemon.hasTakeableItem().should.be.false

    it "returns true if the item can be taken", ->
      pokemon = new Pokemon(item: "Leftovers")
      pokemon.hasTakeableItem().should.be.true

    it "returns false if the pokemon has a mail", ->
      pokemon = new Pokemon(item: "Air Mail")
      pokemon.hasTakeableItem().should.be.false

    it "returns false if the pokemon has a key item", ->
      pokemon = new Pokemon(item: "Acro Bike")
      pokemon.hasTakeableItem().should.be.false

    it "returns false if the pokemon has Multitype and a plate", ->
      pokemon = new Pokemon(ability: "Multitype", item: "Draco Plate")
      pokemon.hasTakeableItem().should.be.false

    it "returns false if the pokemon is Giratina-O", ->
      pokemon = new Pokemon(name: "Giratina", forme: "origin", item: "Griseous Orb")
      pokemon.hasTakeableItem().should.be.false

    it "returns false if the pokemon is Genesect with a Drive item", ->
      pokemon = new Pokemon(name: "Genesect", item: "Burn Drive")
      pokemon.hasTakeableItem().should.be.false

  describe "#isWeatherDamageImmune", ->
    it "returns true if it's hailing and the Pokemon is Ice type", ->
      pokemon = new Pokemon()
      pokemon.types = [ "Ice" ]
      pokemon.isWeatherDamageImmune(Weather.HAIL).should.be.true

    it "returns true if it's sandstorming and the Pokemon is Rock type", ->
      pokemon = new Pokemon()
      pokemon.types = [ "Rock" ]
      pokemon.isWeatherDamageImmune(Weather.SAND).should.be.true

    it "returns true if it's sandstorming and the Pokemon is Steel type", ->
      pokemon = new Pokemon()
      pokemon.types = [ "Steel" ]
      pokemon.isWeatherDamageImmune(Weather.SAND).should.be.true

    it "returns true if it's sandstorming and the Pokemon is Ground type", ->
      pokemon = new Pokemon()
      pokemon.types = [ "Ground" ]
      pokemon.isWeatherDamageImmune(Weather.SAND).should.be.true

    it "returns false otherwise", ->
      pokemon = new Pokemon()
      pokemon.types = [ "Grass" ]
      pokemon.isWeatherDamageImmune(Weather.SAND).should.be.false
      pokemon.isWeatherDamageImmune(Weather.HAIL).should.be.false

  describe "#useItem", ->
    it "records the item in lastItem", ->
      pokemon = new Pokemon(item: "Leftovers")
      pokemon.switchIn()
      pokemon.useItem()
      should.exist pokemon.lastItem
      pokemon.lastItem.displayName.should.equal("Leftovers")

    it "removes the item", ->
      pokemon = new Pokemon(item: "Leftovers")
      pokemon.switchIn()
      pokemon.useItem()
      pokemon.hasItem().should.be.false

  describe "#removeItem", ->
    it "removes the item", ->
      pokemon = new Pokemon(item: "Leftovers")
      pokemon.switchIn()
      pokemon.removeItem()
      pokemon.hasItem().should.be.false

    it "removes prior records of an item", ->
      pokemon = new Pokemon(item: "Flying Gem")
      fake = new Pokemon(item: "Leftovers")
      pokemon.switchIn()
      fake.switchIn()
      pokemon.useItem()
      pokemon.setItem(fake.getItem())
      pokemon.removeItem()
      should.not.exist pokemon.lastItem

  describe '#changeForme', ->
    it "changes the Pokemon's forme from one to another", ->
      pokemon = new Pokemon(name: 'Shaymin')
      pokemon.forme.should.equal('default')
      pokemon.changeForme('sky')
      pokemon.forme.should.equal('sky')

    it 'changes base stats if applicable', ->
      pokemon = new Pokemon(name: 'Shaymin')
      pokemon.baseStats.should.eql(
        attack: 100, defense: 100, hp: 100,
        specialAttack: 100, specialDefense: 100, speed: 100)
      pokemon.changeForme('sky')
      pokemon.baseStats.should.eql(
        attack: 103, defense: 75, hp: 100,
        specialAttack: 120, specialDefense: 75, speed: 127)

    it 'changes weight if applicable', ->
      pokemon = new Pokemon(name: 'Shaymin')
      pokemon.weight.should.equal(21)
      pokemon.changeForme('sky')
      pokemon.weight.should.equal(52)

    it 'changes type if applicable', ->
      pokemon = new Pokemon(name: 'Shaymin')
      pokemon.types.should.eql([ 'Grass' ])
      pokemon.changeForme('sky')
      pokemon.types.should.eql([ 'Grass', 'Flying' ])

    it 'does nothing if the new forme is an invalid forme', ->
      pokemon = new Pokemon(name: 'Shaymin')
      pokemon.forme.should.equal('default')
      pokemon.changeForme('batman')
      pokemon.forme.should.equal('default')

  describe "#toJSON", ->
    it "can hide information", ->
      pokemon = new Pokemon(name: 'Shaymin')
      json = pokemon.toJSON(hidden: true)
      json.should.not.have.property("hp")
      json.should.not.have.property("maxHP")
      json.should.not.have.property("moves")
      json.should.not.have.property("moveTypes")
      json.should.not.have.property("pp")
      json.should.not.have.property("maxPP")
      json.should.not.have.property("ivs")

    it "shows all information otherwise", ->
      pokemon = new Pokemon(name: 'Shaymin')
      json = pokemon.toJSON()
      json.should.have.property("hp")
      json.should.have.property("maxHP")
      json.should.have.property("moves")
      json.should.have.property("moveTypes")
      json.should.have.property("pp")
      json.should.have.property("maxPP")
      json.should.have.property("ivs")
