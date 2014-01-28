{User} = require('./user')

class @Room
  constructor: (@name) ->
    @users = []
    @counts = {}

  # Adds a user to this room.
  # Returns the number of connections that this user has.
  addUser: (user) ->
    {id} = user
    @counts[id] ||= 0
    @users.push(user)
    @counts[id] += 1
    @counts[id]

  # Removes a user from this room.
  # Returns the number of remaining connections this user has.
  removeUser: (user) ->
    {id} = user
    count = @counts[id]
    return 0  if !count
    @counts[id] -= 1

    # Remove the user from the user array.
    for element, i in @users
      if id == element.id
        @users.splice(i, 1)
        break

    # Remove the user from the user array if there are no more.
    delete @counts[id]  if @counts[id] == 0
    @counts[id] || 0

  userMessage: (user, message) ->
    @send('update chat', user.id, message)

  message: (message) ->
    @send('raw message', message)

  send: ->
    for user in @users
      user.send?.apply(user, arguments)

  find: (id) ->
    for user in @users
      if user.id == id
        return user
    return null

  # Alias for #find
  get: this::find

  has: (id) ->
    !!@find(id)

  kick: (user) ->
    user = @find(user)  if user not instanceof User
    user.close()
    count = 1
    count = @removeUser(user)  while count > 0

  userJSON: ->
    @users.map (user) ->
      user.toJSON()
