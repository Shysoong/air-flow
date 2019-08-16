lodash = require('lodash')
util = require('../modules/util')

module.exports = (_, _message, _opts={}, _go) ->
  lodash.defaults _opts,
    title: '确认'
    acceptCaption: '是'
    declineCaption: '否'

  accept = -> _go yes

  decline = -> _go no

  title: _opts.title
  acceptCaption: _opts.acceptCaption
  declineCaption: _opts.declineCaption
  message: util.multilineTextToHTML _message
  accept: accept
  decline: decline
  template: 'confirm-dialog'

