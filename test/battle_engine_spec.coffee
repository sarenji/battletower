sinon = require 'sinon'
{items} = require('../data/bw')
{Battle, Pokemon, Status, VolatileStatus} = require('../').server
{Factory} = require './factory'

describe 'Mechanics', ->
  create = (opts={}) ->
    @id1 = 'abcde'
    @id2 = 'fghij'
    @player1 = opts.player1 || {id: @id1, emit: ->}
    @player2 = opts.player2 || {id: @id2, emit: ->}
    team1   = opts.team1
    team2   = opts.team2
    players = [{player: @player1, team: team1},
               {player: @player2, team: team2}]
    @battle = new Battle('id', players: players)
    sinon.stub(@battle.rng, 'next', -> 1)          # no chs
    sinon.stub(@battle.rng, 'randInt', -> 0)       # always do max damage
    sinon.stub(@battle.rng, 'willMiss', -> false)  # never miss
    @team1  = @battle.getTeam(@player1.id)
    @team2  = @battle.getTeam(@player2.id)

  describe 'splash', ->
    it 'does no damage', ->
      create.call this,
        team1: [Factory('Magikarp')]
        team2: [Factory('Magikarp')]
      defender = @team2.at(0)
      originalHP = defender.currentHP
      @battle.makeMove(@player1, 'splash')
      @battle.continueTurn()
      defender.currentHP.should.equal originalHP

  describe 'an attack missing', ->
    it 'deals no damage', ->
      create.call this,
        team1: [Factory('Celebi')]
        team2: [Factory('Magikarp')]
      @battle.rng.willMiss.restore()
      sinon.stub(@battle.rng, 'willMiss', -> true)
      defender = @team2.at(0)
      originalHP = defender.currentHP
      @battle.makeMove(@player1, 'leaf-storm')
      @battle.continueTurn()
      defender.currentHP.should.equal originalHP

    it 'triggers effects dependent on the move missing', ->
      create.call this,
        team1: [Factory('Hitmonlee')]
        team2: [Factory('Magikarp')]
      @battle.rng.willMiss.restore()
      sinon.stub(@battle.rng, 'willMiss', -> true)
      originalHP = @team1.at(0).currentHP
      @battle.makeMove(@player1, 'hi-jump-kick')
      @battle.continueTurn()
      damage = 312
      (originalHP - @team1.at(0).currentHP).should.equal Math.floor(damage / 2)

    it 'does not trigger effects dependent on the move hitting', ->
      create.call this,
        team1: [Factory('Celebi')]
        team2: [Factory('Gyarados')]
      @battle.rng.willMiss.restore()
      sinon.stub(@battle.rng, 'willMiss', -> true)
      @battle.makeMove(@player1, 'leaf-storm')
      @battle.continueTurn()
      @team1.at(0).stages.specialAttack.should.equal 0

  describe 'an attack with perfect accuracy', ->
    it 'can never miss'

  describe 'fainting', ->
    it 'forces a new pokemon to be picked', ->
      create.call this,
        team1: [Factory('Mew'), Factory('Heracross')]
        team2: [Factory('Hitmonchan'), Factory('Heracross')]
      @team2.at(0).currentHP = 1
      spy = sinon.spy(@player2, 'emit')
      @battle.makeMove(@player1, 'Psychic')
      @battle.makeMove(@player2, 'Mach Punch')
      spy.calledWith('request action').should.be.true

    it 'does not increment the turn count', ->
      create.call this,
        team1: [Factory('Mew'), Factory('Heracross')]
        team2: [Factory('Hitmonchan'), Factory('Heracross')]
      turn = @battle.turn
      @team2.at(0).currentHP = 1
      @battle.makeMove(@player1, 'Psychic')
      @battle.makeMove(@player2, 'Mach Punch')
      @battle.turn.should.not.equal turn + 1

    it 'removes the fainted pokemon from the action priority queue', ->
      create.call this,
        team1: [Factory('Mew'), Factory('Heracross')]
        team2: [Factory('Hitmonchan'), Factory('Heracross')]
      turn = @battle.turn
      @team1.at(0).currentHP = 1
      @team2.at(0).currentHP = 1
      @battle.makeMove(@player1, 'Psychic')
      @battle.makeMove(@player2, 'Mach Punch')
      @team1.at(0).currentHP.should.be.below 1
      @team2.at(0).currentHP.should.equal 1

    it 'lets the player switch in a new pokemon', ->
      create.call this,
        team1: [Factory('Mew'), Factory('Heracross')]
        team2: [Factory('Hitmonchan'), Factory('Heracross')]
      @team2.at(0).currentHP = 1
      @battle.makeMove(@player1, 'Psychic')
      @battle.makeMove(@player2, 'Mach Punch')
      @battle.makeSwitch(@player2, 'Heracross')
      @team2.at(0).name.should.equal 'Heracross'

  describe 'secondary effect attacks', ->
    it 'can inflict effect on successful hit', ->
      create.call this,
        team1: [Factory('Porygon-Z')]
        team2: [Factory('Porygon-Z')]
      @battle.rng.next.restore()
      sinon.stub(@battle.rng, 'next', -> 0)     # 100% chance
      defender = @team2.at(0)
      @battle.makeMove(@player1, 'flamethrower')
      @battle.continueTurn()
      defender.hasStatus(Status.BURN).should.be.true

  describe 'the fang attacks', ->
    it 'can inflict two effects at the same time', ->
      create.call this,
        team1: [Factory('Gyarados')]
        team2: [Factory('Gyarados')]
      @battle.rng.next.restore()
      sinon.stub(@battle.rng, 'next', -> 0)     # 100% chance
      defender = @team2.at(0)
      @battle.makeMove(@player1, 'ice-fang')
      @battle.continueTurn()
      defender.hasAttachment(VolatileStatus.FLINCH).should.be.true
      defender.hasStatus(Status.FREEZE).should.be.true

  describe 'drain attacks', ->
    it 'recovers a percentage of the damage dealt, rounded down', ->
      create.call this,
        team1: [Factory('Conkeldurr')]
        team2: [Factory('Hitmonchan')]
      startHP = 1
      @team1.at(0).currentHP = startHP
      hp = @team2.at(0).currentHP
      @battle.makeMove(@player1, 'drain-punch')
      @battle.continueTurn()
      damage = (hp - @team2.at(0).currentHP)
      (@team1.at(0).currentHP - startHP).should.equal Math.floor(damage / 2)

    it 'cannot recover to over 100% HP', ->
      create.call this,
        team1: [Factory('Conkeldurr')]
        team2: [Factory('Hitmonchan')]
      hp = @team1.at(0).currentHP = @team1.at(0).stat('hp')
      @battle.makeMove(@player1, 'drain-punch')
      @battle.continueTurn()
      (@team1.at(0).currentHP - hp).should.equal 0

  describe 'a pokemon using a primary boosting move', ->
    it "doesn't do damage if base power is 0", ->
      create.call this,
        team1: [Factory('Gyarados')]
        team2: [Factory('Hitmonchan')]
      @battle.makeMove(@player1, 'dragon-dance')
      @battle.continueTurn()
      @team2.at(0).currentHP.should.equal @team2.at(0).stat('hp')

    it "deals damage and boosts stats if base power is >0", ->
      create.call this,
        team1: [Factory('Celebi')]
        team2: [Factory('Gyarados')]
      hp = @team2.at(0).currentHP
      @battle.makeMove(@player1, 'leaf-storm')
      @battle.continueTurn()
      @team1.at(0).stages.specialAttack.should.equal -2
      (hp - @team2.at(0).currentHP).should.equal 178

    it "boosts the pokemon's stats", ->
      create.call this,
        team1: [Factory('Gyarados')]
        team2: [Factory('Hitmonchan')]
      attack = @team1.at(0).stat('attack')
      speed  = @team1.at(0).stat('speed')
      @battle.makeMove(@player1, 'dragon-dance')
      @battle.continueTurn()
      @team1.at(0).stages.should.include attack: 1, speed: 1

    it "has the boosts removed on switch"

  describe 'a pokemon using a move with a secondary boosting effect', ->
    it "has a chance to activate", ->
      create.call this,
        team1: [Factory('Mew')]
        team2: [Factory('Hitmonchan')]
      @battle.rng.next.restore()
      sinon.stub(@battle.rng, 'next', -> 0)     # 100% chance
      attack = @team1.at(0).stat('attack')
      speed  = @team1.at(0).stat('speed')
      @battle.makeMove(@player1, 'ancientpower')
      @battle.continueTurn()
      @team1.at(0).stages.should.include {
        attack: 1, defense: 1, speed: 1, specialAttack: 1, specialDefense: 1
      }

  describe 'a pokemon using Acrobatics', ->
    it 'gets double the base power without an item', ->
      create.call this,
        team1: [Factory('Gliscor')]
        team2: [Factory('Regirock')]
      hp = @team2.at(0).currentHP
      @battle.makeMove(@player1, 'acrobatics')
      @battle.continueTurn()
      damage = (hp - @team2.at(0).currentHP)
      damage.should.equal 36

    it 'has normal base power with an item', ->
      create.call this,
        team1: [Factory('Gliscor', item: 'Leftovers')]
        team2: [Factory('Regirock')]
      hp = @team2.at(0).currentHP
      @battle.makeMove(@player1, 'acrobatics')
      @battle.continueTurn()
      damage = (hp - @team2.at(0).currentHP)
      damage.should.equal 18

  describe 'a pokemon using a standard recoil move', ->
    it 'receives a percentage of the damage rounded down', ->
      create.call this,
        team1: [Factory('Blaziken')]
        team2: [Factory('Gliscor')]
      startHP = @team1.at(0).currentHP
      hp = @team2.at(0).currentHP
      @battle.makeMove(@player1, 'brave-bird')
      @battle.continueTurn()
      damage = (hp - @team2.at(0).currentHP)
      (startHP - @team1.at(0).currentHP).should.equal Math.floor(damage / 3)

  describe 'a pokemon with technician', ->
    it "doesn't increase damage if the move has bp > 60", ->
      create.call this,
        team1: [Factory('Hitmonchan')]
        team2: [Factory('Mew')]
      @battle.makeMove(@player1, 'Ice Punch')
      hp = @team2.at(0).currentHP
      @battle.continueTurn()
      (hp - @team2.at(0).currentHP).should.equal 84

    it "increases damage if the move has bp <= 60", ->
      create.call this,
        team1: [Factory('Hitmonchan')]
        team2: [Factory('Shaymin (land)')]
      @battle.makeMove(@player1, 'Bullet Punch')
      hp = @team2.at(0).currentHP
      @battle.continueTurn()
      (hp - @team2.at(0).currentHP).should.equal 67

  describe 'STAB', ->
    it "gets applied if the move and user share a type", ->
      create.call this,
        team1: [Factory('Heracross')]
        team2: [Factory('Regirock')]
      @battle.makeMove(@player1, 'Megahorn')
      hp = @team2.at(0).currentHP
      @battle.continueTurn()
      (hp - @team2.at(0).currentHP).should.equal 123

    it "doesn't get applied if the move and user are of different types", ->
      create.call this,
        team1: [Factory('Hitmonchan')]
        team2: [Factory('Mew')]
      @battle.makeMove(@player1, 'Ice Punch')
      hp = @team2.at(0).currentHP
      @battle.continueTurn()
      (hp - @team2.at(0).currentHP).should.equal 84

    it 'is 2x if the pokemon has Adaptability', ->
      create.call this,
        team1: [Factory('Porygon-Z')]
        team2: [Factory('Mew')]
      @battle.makeMove(@player1, 'Tri Attack')
      hp = @team2.at(0).currentHP
      @battle.continueTurn()
      (hp - @team2.at(0).currentHP).should.equal 214

  describe 'turn order', ->
    it 'randomly decides winner if pokemon have the same speed and priority', ->
      create.call this,
        team1: [Factory('Mew')]
        team2: [Factory('Mew')]
      spy = sinon.spy(@battle, 'orderIds')
      @battle.makeMove(@player1, 'Psychic')
      @battle.makeMove(@player2, 'Psychic')
      spy.returned([@id2, @id1]).should.be.true
      @battle.rng.next.restore()

      sinon.stub(@battle.rng, 'next', -> .4)
      @battle.makeMove(@player1, 'Psychic')
      @battle.makeMove(@player2, 'Psychic')
      spy.returned([@id1, @id2]).should.be.true

    it 'decides winner by highest priority move', ->
      create.call this,
        team1: [Factory('Hitmonchan')]
        team2: [Factory('Hitmonchan')]
      spy = sinon.spy(@battle, 'orderIds')
      @battle.makeMove(@player1, 'Mach Punch')
      @battle.makeMove(@player2, 'ThunderPunch')
      spy.returned([@id1, @id2]).should.be.true
      @battle.rng.next.restore()

      @battle.makeMove(@player1, 'ThunderPunch')
      @battle.makeMove(@player2, 'Mach Punch')
      spy.returned([@id2, @id1]).should.be.true

    it 'decides winner by speed if priority is equal', ->
      create.call this,
        team1: [Factory('Hitmonchan')]
        team2: [Factory('Hitmonchan')]
      spy = sinon.spy(@battle, 'orderIds')
      @battle.makeMove(@player1, 'ThunderPunch')
      @battle.makeMove(@player2, 'ThunderPunch')
      spy.returned([@id2, @id1]).should.be.true

  describe 'fainting all the opposing pokemon', ->
    it "doesn't request any more actions from players", ->
      create.call this,
        team1: [Factory('Hitmonchan')]
        team2: [Factory('Mew')]
      @team2.at(0).currentHP = 1
      @battle.makeMove(@player1, 'Mach Punch')
      @battle.makeMove(@player2, 'Psychic')
      @battle.requests.should.not.have.property @player1.id
      @battle.requests.should.not.have.property @player2.id

    it 'ends the battle', ->
      create.call this,
        team1: [Factory('Hitmonchan')]
        team2: [Factory('Mew')]
      @team2.at(0).currentHP = 1
      mock = sinon.mock(@battle)
      mock.expects('endBattle').once()
      @battle.makeMove(@player1, 'Mach Punch')
      @battle.makeMove(@player2, 'Psychic')
      mock.verify()
