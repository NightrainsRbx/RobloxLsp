local guide = require 'core.guide'

return function (source)
    if not source.generics then
        return ''
    end
    return guide.buildTypeAnn(source.generics)
end
