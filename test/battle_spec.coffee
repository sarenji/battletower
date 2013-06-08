sinon = require 'sinon'
{Battle, Pokemon, Weather} = require('../').server
{Factory} = require('./factory')
{moves} = require('../data/bw')
should = require 'should'

describe 'Battle', ->
  beforeEach ->
    @id1 = 'abcde'
    @id2 = 'fghij'
    @player1 = {id: @id1}
    @player2 = {id: @id2}
    team1   = [Factory('Hitmonchan'), Factory('Heracross')]
    team2   = [Factory('Hitmonchan'), Factory('Heracross')]
    players = [{player: @player1, team: team1},
               {player: @player2, team: team2}]
    @battle = new Battle('id', players: players)
    @team1  = @battle.getTeam(@id1)
    @team2  = @battle.getTeam(@id2)

    @battle.beginTurn()

  it 'starts at turn 1', ->
    @battle.turn.should.equal 1

  describe '#hasWeather(weatherName)', ->
    it 'returns true if the current battle weather is weatherName', ->
      @battle.weather = "Sunny"
      @battle.hasWeather("Sunny").should.be.true

    it 'returns false on non-None in presence of a weather-cancel ability', ->
      @battle.weather = "Sunny"
      sinon.stub(@battle, 'hasWeatherCancelAbilityOnField', -> true)
      @battle.hasWeather("Sunny").should.be.false

    it 'returns true on None in presence of a weather-cancel ability', ->
      @battle.weather = "Sunny"
      sinon.stub(@battle, 'hasWeatherCancelAbilityOnField', -> true)
      @battle.hasWeather("None").should.be.true

  describe '#recordMove', ->
    it "records a player's move", ->
      @battle.recordMove(@id1, moves['tackle'])
      @battle.playerActions.should.have.property @id1
      @battle.playerActions[@id1].move.name.should.equal 'tackle'

  describe '#recordSwitch', ->
    it "records a player's switch", ->
      @battle.recordSwitch(@id1, 1)
      @battle.playerActions.should.have.property @id1
      @battle.playerActions[@id1].to.should.equal 1

  describe '#performSwitch', ->
    it "swaps pokemon positions of a player's team", ->
      [poke1, poke2] = @team1.pokemon
      @battle.performSwitch(@id1, 1)
      @team1.pokemon.slice(0, 2).should.eql [poke2, poke1]

    it "calls the pokemon's switchOut() method", ->
      pokemon = @team1.first()
      mock = sinon.mock(pokemon)
      mock.expects('switchOut').once()
      @battle.performSwitch(@id1, 1)
      mock.verify()

  describe "#setWeather", ->
    it "can last a set number of turns", ->
      @battle.setWeather(Weather.SUN, 5)
      for i in [0...5]
        @battle.endTurn()
      @battle.weather.should.equal Weather.NONE

  describe "weather", ->
    it "damages pokemon who are not of a certain type", ->
      @battle.setWeather(Weather.SAND)
      @battle.endTurn()
      maxHP = @team1.first().stat('hp')
      (maxHP - @team1.first().currentHP).should.equal Math.floor(maxHP / 16)
      (maxHP - @team2.first().currentHP).should.equal Math.floor(maxHP / 16)

      @battle.setWeather(Weather.HAIL)
      @battle.endTurn()
      maxHP = @team1.first().stat('hp')
      (maxHP - @team1.first().currentHP).should.equal 2*Math.floor(maxHP / 16)
      (maxHP - @team2.first().currentHP).should.equal 2*Math.floor(maxHP / 16)

  describe "move PP", ->
    it "goes down after a pokemon uses a move", ->
      pokemon = @team1.first()
      move = pokemon.moves[0]
      @battle.performMove(@id1, move)
      pokemon.pp(move).should.equal(pokemon.maxPP(move) - 1)

  describe "#performMove", ->
    it "records this move as the battle's last move", ->
      pokemon = @team1.first()
      move = pokemon.moves[0]
      @battle.performMove(@id1, move)

      should.exist @battle.lastMove
      @battle.lastMove.should.equal move
