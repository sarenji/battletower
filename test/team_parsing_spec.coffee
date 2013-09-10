{PokeBattle} = require '../client/app/js/concerns/team_parsing'

require 'sugar'
should = require 'should'
require './helpers'

describe "Client", ->
  describe "parsing teams", ->
    beforeEach ->
      @teamString = """
Swampert @ Leftovers
Trait: Torrent
EVs: 252 HP / 252 Def / 4 SDef
Relaxed Nature
- Surf
- Ice Beam
- Earthquake
- Protect

Poop (Blissey) (F) @ Leftovers
Trait: Natural Cure
Shiny: Yes
EVs: 176 HP / 252 Def / 80 SDef
Bold Nature
- Seismic Toss
- Aromatherapy

Skarmory (M)

Tyranitar
Level: 1
Happiness: 3
EVs: 252 HP / 80 Def / 176 SDef
- Hidden Power [Grass]

Articuno
IVs: 30 HP / 29 Def
- Hidden Power [Fire]

"""
    it "converts a team to an array readable by this simulator", ->
      team = PokeBattle.parseTeam(@teamString)

      pokemon = team[0]
      pokemon.name.should.equal("Swampert")
      pokemon.should.not.have.property('gender')
      pokemon.item.should.equal("Leftovers")
      pokemon.ability.should.equal("Torrent")
      pokemon.nature.should.equal("Relaxed")
      pokemon.should.not.have.property('level')
      pokemon.should.not.have.property('happiness')
      pokemon.should.not.have.property('shiny')
      pokemon.should.not.have.property('ivs')
      pokemon.evs.should.eql(hp: 252, defense: 252, specialDefense: 4)
      pokemon.moves.should.eql([ "Surf", "Ice Beam", "Earthquake", "Protect"])

      pokemon = team[1]
      pokemon.name.should.equal("Blissey")
      pokemon.gender.should.equal("F")
      pokemon.item.should.equal("Leftovers")
      pokemon.ability.should.equal("Natural Cure")
      pokemon.nature.should.equal("Bold")
      pokemon.should.not.have.property('level')
      pokemon.should.not.have.property('happiness')
      pokemon.shiny.should.be.true
      pokemon.should.not.have.property('ivs')
      pokemon.evs.should.eql(hp: 176, defense: 252, specialDefense: 80)
      pokemon.moves.should.eql(["Seismic Toss", "Aromatherapy"])

      pokemon = team[2]
      pokemon.name.should.equal("Skarmory")
      pokemon.gender.should.equal("M")
      pokemon.should.not.have.property('item')
      pokemon.should.not.have.property('ability')
      pokemon.should.not.have.property('nature')
      pokemon.should.not.have.property('level')
      pokemon.should.not.have.property('happiness')
      pokemon.should.not.have.property('shiny')
      pokemon.should.not.have.property('ivs')
      pokemon.should.not.have.property('evs')
      pokemon.should.not.have.property('moves')

      pokemon = team[3]
      pokemon.name.should.equal("Tyranitar")
      pokemon.should.not.have.property('gender')
      pokemon.should.not.have.property('item')
      pokemon.should.not.have.property('ability')
      pokemon.should.not.have.property('nature')
      pokemon.level.should.equal(1)
      pokemon.happiness.should.equal(3)
      pokemon.should.not.have.property('shiny')
      pokemon.ivs.should.eql(attack: 30, specialAttack: 30)
      pokemon.evs.should.eql(hp: 252, defense: 80, specialDefense: 176)
      pokemon.moves.should.eql(["Hidden Power"])

      pokemon = team[4]
      pokemon.name.should.equal("Articuno")
      pokemon.should.not.have.property('gender')
      pokemon.should.not.have.property('item')
      pokemon.should.not.have.property('ability')
      pokemon.should.not.have.property('nature')
      pokemon.should.not.have.property('level')
      pokemon.should.not.have.property('happiness')
      pokemon.should.not.have.property('shiny')
      # IVs that were explicitly set override Hidden Power!
      pokemon.ivs.should.eql(hp: 30, defense: 29)
      pokemon.should.not.have.property('evs')
      pokemon.moves.should.eql(['Hidden Power'])

  describe "parsing formes", ->
    it "takes into account differing styles of formes", ->
      formes =
        "Thundurus-Therian": ["Thundurus", "therian"]
        "Thundurus-T": ["Thundurus", "therian"]
        "Thundurus": ["Thundurus", null]

        "Shaymin-Sky": ["Shaymin", "sky"]
        "Shaymin-S": ["Shaymin", "sky"]
        "Shaymin": ["Shaymin", null]

        "Giratina-Origin": ["Giratina", "origin"]
        "Giratina-O": ["Giratina", "origin"]
        "Giratina": ["Giratina", null]

        "Arceus-Dark": ["Arceus", null]
        "Arceus": ["Arceus", null]

        "Kyurem-Black": ["Kyurem", "black"]
        "Kyurem-B": ["Kyurem", "black"]
        "Kyurem-White": ["Kyurem", "white"]
        "Kyurem-W": ["Kyurem", "white"]
        "Kyurem": ["Kyurem", null]

        "Rotom-Wash": ["Rotom", "wash"]
        "Rotom-W": ["Rotom", "wash"]
        "Rotom-Fan": ["Rotom", "fan"]
        "Rotom-S": ["Rotom", "fan"]
        "Rotom-Heat": ["Rotom", "heat"]
        "Rotom-H": ["Rotom", "heat"]
        "Rotom-Frost": ["Rotom", "frost"]
        "Rotom-F": ["Rotom", "frost"]
        "Rotom-Mow": ["Rotom", "mow"]
        "Rotom-C": ["Rotom", "mow"]
        "Rotom": ["Rotom", null]

        "Deoxys-Attack": ["Deoxys", "attack"]
        "Deoxys-A": ["Deoxys", "attack"]
        "Deoxys-Defense": ["Deoxys", "defense"]
        "Deoxys-D": ["Deoxys", "defense"]
        "Deoxys-Speed": ["Deoxys", "speed"]
        "Deoxys-S": ["Deoxys", "speed"]
        "Deoxys": ["Deoxys", null]

      teamArray = (pokemonName  for pokemonName of formes)
      teamFormes = (forme  for forme in teamArray)

      teamArray.unshift('')
      teamArray.push('')
      teamString = teamArray.join('\n\n')
      team = PokeBattle.parseTeam(teamString)

      for member, i in team
        [species, forme] = formes[teamFormes[i]]
        should.exist(member)
        member.should.have.property('name')
        member.name.should.equal(species)
        if forme
          member.should.have.property('forme')
          member.forme.should.equal(forme)
