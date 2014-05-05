{_} = require('underscore')
auth = require('./auth')
ratings = require('./ratings')
errors = require('../shared/errors')

exports.Commands = Commands = {}
exports.HelpDescriptions = HelpDescriptions = {}

desc = (description) ->
  desc.lastDescription = description

parseArguments = (args) ->
  args = Array::slice.call(args, 0)
  hash = {}
  if typeof args[args.length - 1] == 'function'
    hash.callback = args.pop()
  hash.args = args
  hash

makeCommand = (commandNames..., func) ->
  HelpDescriptions[commandNames[0]] = desc.lastDescription || ""
  for commandName in commandNames
    Commands[commandName] = func
  delete desc.lastDescription

makeModCommand = (commandNames..., func) ->
  func.authority = auth.levels.MOD
  makeCommand(commandNames..., func)

makeAdminCommand = (commandNames..., func) ->
  func.authority = auth.levels.ADMIN
  makeCommand(commandNames..., func)

makeOwnerCommand = (commandNames..., func) ->
  func.authority = auth.levels.OWNER
  makeCommand(commandNames..., func)

@executeCommand = (server, user, room, commandName, args...) ->
  {args, callback} = parseArguments(args)
  callback ||= ->
  func = Commands[commandName]
  if !func
    message = "Invalid command: #{commandName}. Type /help to see a list."
    user.error(errors.COMMAND_ERROR, message)
    callback()
  else if !func.authority || user.authority >= func.authority
    Commands[commandName]?.call(server, user, room, callback, args...)
  else
    user.error(errors.COMMAND_ERROR, "You have insufficient authority.")
    callback()

#######################
# Command definitions #
#######################

desc "Gets a single username's rating on this server. Usage: /rating username"
makeCommand "rating", "ranking", (user, room, next, username) ->
  username ||= user.id
  ratings.getRating username, (err, rating) ->
    ratings.getRatio username, (err, ratios) ->
      if err then return user.error(errors.COMMAND_ERROR, err.message)
      ratio = ["Win: #{ratios.win}"]
      if user.id == username
        total = _.reduce(_.values(ratios), ((x, y) -> x + y), 0)
        ratio.push("Lose: #{ratios.lose}")
        ratio.push("Tie: #{ratios.draw}")
        ratio.push("Total: #{total}")
      user.message("#{username}'s rating: #{rating} (#{ratio.join(' / ')})")
      next()

desc "Finds all the battles a username is playing in on this server.
      Usage: /battles username"
makeCommand "battles", (user, room, next, username) ->
  if !username
    user.error(errors.COMMAND_ERROR, "Usage: /battles username")
    return next()
  battleIds = @getVisibleUserBattles(username)
  links = battleIds.map (id) ->
    "<span class='fake_link spectate' data-battle-id='#{id}'>#{id[...6]}</span>"
  user.message("#{username}'s battles: #{links.join(" | ")}")
  next()

desc "Mutes a username for 10 minutes. The reason is optional. Usage: /mute username, reason"
makeModCommand "mute", (user, room, next, username, reason...) ->
  if !username
    user.error(errors.COMMAND_ERROR, "Usage: /mute username, reason")
    return next()
  reason = reason.join(',').trim()
  @mute(username, reason, 10 * 60)
  message = "#{user.id} muted #{username} for 10 minutes"
  message += " (#{reason})"  if reason.length > 0
  room.message(message)
  next()

desc "Unmutes a username. Usage: /unmute username"
makeModCommand "unmute", (user, room, next, username) ->
  if !username
    user.error(errors.COMMAND_ERROR, "Usage: /unmute username")
    return next()
  auth.getMuteTTL username, (err, ttl) =>
    if ttl == -2
      user.error(errors.COMMAND_ERROR, "#{username} is already unmuted!")
      return next()
    else
      @unmute(username)
      message = "#{user.id} unmuted #{username}"
      room.message(message)
      next()

desc "Kicks a username for 3 minutes. The reason is optional. Usage: /kick username, reason"
makeModCommand "kick", (user, room, next, username, reason...) ->
  if !username
    user.error(errors.COMMAND_ERROR, "Usage: /kick username,reason")
    return next()
  else if !room.has(username)
    user.error(errors.COMMAND_ERROR, "User #{username} is not online.")
    return next()
  reason = reason.join(',').trim()
  @ban(username, reason, 3 * 60)
  message = "#{user.id} kicked #{username} for 3 minutes"
  message += " (#{reason})"  if reason.length > 0
  room.message(message)
  next()

desc "Bans a username. The reason is optional. Usage: /ban username, reason"
makeModCommand "ban", (user, room, next, username, reason...) ->
  if !username
    user.error(errors.COMMAND_ERROR, "Usage: /ban username, reason")
    return next()
  reason = reason.join(',').trim()
  @ban(username, reason)
  message = "#{user.id} banned #{username}"
  message += " (#{reason})"  if reason.length > 0
  room.message(message)
  next()

desc "Unbans a username. Usage: /unban username"
makeModCommand "unban", (user, room, next, username) ->
  if !username
    user.error(errors.COMMAND_ERROR, "Usage: /unban username")
    return next()
  auth.getBanTTL username, (err, ttl) =>
    if ttl == -2
      user.error(errors.COMMAND_ERROR, "#{username} is already unbanned!")
      return next()
    else
      @unban username, =>
        message = "#{user.id} unbanned #{username}"
        room.message(message)
        return next()

desc "Prevents new battles from starting. Usage: /lockdown [on|off]"
makeAdminCommand "lockdown", (user, room, next, option = "on") ->
  if option not in [ "on", "off" ]
    user.error(errors.COMMAND_ERROR, "Usage: /lockdown [on|off]")
    return next()
  if option == 'on' then @lockdown() else @unlockdown()
  next()

desc "Mods a username permanently. Usage: /mod username"
makeAdminCommand "mod", (user, room, next, username) ->
  if !username
    user.error(errors.COMMAND_ERROR, "Usage: /mod username")
    return next()
  auth.setAuth username, auth.levels.MOD, (err, result) =>
    if err
      user.error(errors.COMMAND_ERROR, err.message)
      return next()
    @setAuthority(username, auth.levels.MOD)
    return next()

desc "Admins a username permanently. Usage: /admin username"
makeOwnerCommand "admin", (user, room, next, username) ->
  if !username
    user.error(errors.COMMAND_ERROR, "Usage: /admin username")
    return next()
  auth.setAuth username, auth.levels.ADMIN, (err, result) =>
    if err
      user.error(errors.COMMAND_ERROR, err.message)
      return next()
    @setAuthority(username, auth.levels.ADMIN)
    return next()

desc "Deauthes a username permanently. Usage: /deauth username"
makeOwnerCommand "deauth", (user, room, next, username) ->
  if !username
    user.error(errors.COMMAND_ERROR, "Usage: /deauth username")
    return next()
  auth.setAuth username, auth.levels.USER, (err, result) =>
    if err
      user.error(errors.COMMAND_ERROR, err.message)
      return next()
    @setAuthority(username, auth.levels.USER)
    return next()

desc "Changes the topic message. Usage: /topic message"
makeAdminCommand "topic", (user, room, next, topicPieces...) ->
  room.setTopic(topicPieces.join(','))
  next()

desc "Announces something to the entire server. Usage: /wall message"
makeAdminCommand "wall", "announce", (user, room, next, pieces...) ->
  message = pieces.join(',')
  return next()  if !message
  @announce("<strong>#{user.id}:</strong> #{message}")
  next()

desc "Evaluates a script in the context of the server."
makeOwnerCommand "eval", (user, room, next, pieces...) ->
  source = pieces.join(',')
  return next()  if !source
  try
    result = (new Function("with(this) { return #{source} }")).call(this)
    user.message("> #{result}")
  catch e
    user.error(errors.COMMAND_ERROR, "EVAL ERROR: #{e.message}")
  next()

desc "Displays all commands available. Usage: /help"
makeCommand "help", (user, room, next, commandName) ->
  message = []
  for name, description of HelpDescriptions
    message.push("<b>/#{name}:</b> #{description}")
  message = message.join("<br>")
  user.message(message)
  next()
