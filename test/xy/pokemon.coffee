{Weather} = require('../../shared/weather')
{Pokemon} = require('../../server/xy/pokemon')
{Protocol} = require '../../shared/protocol'
{Factory} = require '../factory'
should = require 'should'
shared = require '../shared'

require '../helpers'

describe "XY Pokemon:", ->
  describe '#canMegaEvolve', ->
    it "returns true if holding its associated mega stone", ->
      pokemon = new Pokemon(species: "Charizard", item: "Charizardite Y")
      pokemon.canMegaEvolve().should.be.true

    it "returns false if holding a mega stone meant for another pokemon", ->
      pokemon = new Pokemon(species: "Charizard", item: "Abomasite")
      pokemon.canMegaEvolve().should.be.false

    it "returns false if holding a random item", ->
      pokemon = new Pokemon(species: "Charizard", item: "Leftovers")
      pokemon.canMegaEvolve().should.be.false

    it "returns false if holding no item", ->
      pokemon = new Pokemon(species: "Charizard")
      pokemon.canMegaEvolve().should.be.false

    it "returns false if already another forme", ->
      pokemon = new Pokemon(species: "Charizard", item: "Charizardite X")
      pokemon.changeForme("mega-x")
      pokemon.canMegaEvolve().should.be.false

    it "returns false if the team has already mega evolved", ->
      shared.create.call this,
        gen: 'xy'
        team1: (Factory("Charizard", item: "Charizardite X")  for x in [0..1])
      @team1.first().changeForme("mega-x")
      @team1.at(1).canMegaEvolve().should.be.false

    it "returns true if the team has not already mega evolved", ->
      shared.create.call this,
        gen: 'xy'
        team1: (Factory("Charizard", item: "Charizardite X")  for x in [0..1])
      @team1.at(1).canMegaEvolve().should.be.true

  describe "#blockSwitch", ->
    it "does not block switches if the Pokemon has a Ghost type", ->
      pokemon = new Pokemon(species: "Gengar")
      pokemon.blockSwitch()
      pokemon.isSwitchBlocked().should.be.false

    it "acts normally otherwise", ->
      pokemon = new Pokemon(species: "Charizard")
      pokemon.blockSwitch()
      pokemon.isSwitchBlocked().should.be.true

  describe "#hasTakeableItem", ->
    it "returns false if the pokemon holds a mega stone for its species", ->
      pokemon = new Pokemon(species: "Gengar", item: "Gengarite")
      pokemon.hasTakeableItem().should.be.false

    it "returns true if the pokemon holds a mega stone for another species", ->
      pokemon = new Pokemon(species: "Gengar", item: "Kangaskhanite")
      pokemon.hasTakeableItem().should.be.true

    it "still uses old BW conditions", ->
      pokemon = new Pokemon(species: "Gengar", item: "Leftovers")
      pokemon.hasTakeableItem().should.be.true
      pokemon = new Pokemon(species: "Gengar")
      pokemon.hasTakeableItem().should.be.false
