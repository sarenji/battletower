class @SidebarView extends Backbone.View
  template: JST['navigation']

  events:
    "click .nav_battles li" : 'focusBattle'
    "click .nav_rooms li"   : 'focusRoom'
    "click .nav_battles .close" : 'leaveBattle'
    "click .nav_teambuilder": 'showTeambuilder'

  initialize: (attributes) =>
    @currentWindow = null
    @listenTo(PokeBattle.battles, 'add', @addBattle)
    @listenTo(PokeBattle.battles, 'remove', @removeBattle)
    @listenTo(PokeBattle.battles, 'reset', @resetBattles)
    @listenTo(PokeBattle.battles, 'change:notifications', @renderNotifications)
    @render()

  showTeambuilder: =>
    @changeWindowTo($("#teambuilder-section"), $(".nav_teambuilder"))

  render: =>
    @$el.html @template(battles: PokeBattle.battles)

  renderNotifications: (battle) =>
    $notifications = @$("[data-battle-id='#{battle.id}'] .notifications")

    # We don't want to display notifications if this window is already focused.
    if @currentWindow.data('battle-id') == battle.id
      battle.set('notifications', 0, silent: true)
      $notifications.addClass('hidden')
      return

    # Show notification count.
    notificationCount = battle.get('notifications')
    $notifications.text(notificationCount)
    $notifications.removeClass('hidden')

  addBattle: (battle) =>
    @$(".header_battles, .nav_battles").removeClass("hidden")
    $li = $("""<li class="nav_item fake_link" data-battle-id="#{battle.id}">
      <div class="nav_meta">
        <div class="notifications hidden">0</div>
        <div class="close">x</div>
      </div>#{battle.id}</li>""")
    $li.appendTo(@$('.nav_battles'))
    $li.click()

  removeBattle: (battle) =>
    $navItems = @$(".nav_item")
    $battle = @$(".nav_item[data-battle-id='#{battle.id}']")
    index = $navItems.index($battle)
    $battle.remove()
    if PokeBattle.battles.size() == 0
      @$(".header_battles, .nav_battles").hide()
    $next = $navItems.eq(index - 1)
    $next.click()

  resetBattles: (battles) =>
    for battle in battles
      @addBattle(battle)

  leaveBattle: (e) =>
    $navItem = $(e.currentTarget).closest('.nav_item')
    battleId = $navItem.data('battle-id')
    battle   = PokeBattle.battles.get(battleId)
    # If player is not a spectator and battle is not done, prompt
    if !battle.get('finished') && !battle.get('spectating')
      if !confirm("Are you sure you want to forfeit this battle?") then return
    PokeBattle.battles.remove(battle)
    PokeBattle.socket.send('forfeit', battleId)  if !battle.get('spectating')
    false

  focusBattle: (e) =>
    $this = $(e.currentTarget)
    battleId = $this.data('battle-id')
    console.log "Switching to battle #{battleId}"
    $this.find('.notifications').addClass('hidden')
    $battle = $(""".battle_window[data-battle-id='#{battleId}']""")
    @changeWindowTo($battle, $this)

  focusRoom: (e) =>
    $this = $(e.currentTarget)
    $this.find('.notifications').addClass('hidden')
    # TODO: Remove hardcoding
    $room = $('.chat_window')
    @changeWindowTo($room, $this)

  changeWindowTo: ($toSelector, $navItem) =>
    # Show window, hide others
    $mainContent = $('#main-section')
    $mainContent.children().addClass("hidden")
    @currentWindow = $toSelector.first()
    @currentWindow.removeClass("hidden")
    @currentWindow.find('.chat').trigger('scroll_to_bottom')

    # Add .active to navigation, remove from others
    @$('.nav_item').removeClass('active')
    $navItem.addClass('active')
