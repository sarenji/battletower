JST['battle_actions'] = thermos.template (locals) ->
  actions = locals.validActions
  actionMoves = actions.moves || []
  actionSwitches = actions.switches || []
  @div '.moves.span8', ->
    @h2 "Moves"
    # TODO: if locals.team[0].isAlive()
    @div '.clearfix', ->
      moves = locals.team[0].moves
      moveTypes = locals.team[0].moveTypes
      pps = locals.team[0].pp
      maxPPs = locals.team[0].maxPP
      templ = (i) =>
        [move, moveType, pp, maxPP] = [moves[i], moveTypes[i], pps[i], maxPPs[i]]
        isEnabled = move.toLowerCase().replace(/\s+/g, '-') in actionMoves
        disabledClass = (if !isEnabled then '.disabled' else '')
        moveType = moveType.toLowerCase()
        @div ".move.button.#{moveType}#{disabledClass}", ->
          @div '.main_text', -> move
          @div '.meta_info', ->
            @text pp
            @small "/#{maxPP}"
      for i in [0...moves.length] by 2
        @div '.row-fluid', ->
          @div '.span6', ->
            templ(i)
          @div '.span6', ->
            templ(i + 1)  if i + 1 < moves.length

  @div '.switches.span4', ->
    @h2 "Pokemon"
    for j in [0...locals.team.length] by 3
      @div '.row-fluid', ->
        for i in [j...(j + 3)]
          pokemon = locals.team[i]
          isEnabled = (i in actionSwitches)
          disabledClass = (if !isEnabled then '.disabled' else '')
          data = {slot: i}
          @div '.span4', ->
            @div ".switch.button#{disabledClass}", data: data, ->
              id  = PokemonData[pokemon.name].id
              x   = (id % 16) * 32
              y   = (id >> 4) * 32
              pos = "-#{x}px -#{y}px"
              @span '.pokemon_icon', style: "background-position: #{pos}"
