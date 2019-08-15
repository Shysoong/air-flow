{ link, signal, signals } = require("../modules/dataflow")

exports.init = (_) ->
  _.Version = FLOW_VERSION # global provided by webpack
  _properties = signals []

  link _.ready, ->
    if _.BuildProperties
      _properties _.BuildProperties
    else
      _.requestAbout (error, response) ->
        properties = []

        unless error
          for { name, value } in response.entries
            properties.push
              caption: 'AIR ' + name
              value: value

        properties.push
          caption: 'Flow 版本'
          value: _.Version

        _properties _.BuildProperties = properties

  properties: _properties

