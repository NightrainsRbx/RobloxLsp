local snippet = {}

local function add(cate, key, label)
    return function (text)
        if not snippet[cate] then
            snippet[cate] = {}
        end
        if not snippet[cate][key] then
            snippet[cate][key] = {}
        end
        snippet[cate][key][#snippet[cate][key]+1] = {
            label = label,
            text = text,
        }
    end
end

add('key', 'do', 'do') "do\n\t${0}\nend"

add('key', 'elseif', 'elseif') "elseif ${1} then\n\t${0}"

add('key', 'else', 'else') "else\n\t${0}"

add('key', 'forin', 'for in') "for ${1} in ${2|pairs,ipairs|}(${3}) do\n\t${0}\nend"

add('key', 'for', 'for') "for ${1:i} = ${2}, ${3}, ${4} do\n\t${0}\nend"

add('key', 'function', 'function') "function ${1}(${2})\n\t${0}\nend"

add('key', 'afunction', 'function') "function(${1})\n\t${0}\nend"

add('key', 'if', 'if') "if ${1} then\n\t${0}\nend"

add('key', 'repeat', 'repeat') "repeat\n\t${0}\nuntil"

add('key', 'while', 'while') "while ${1} do\n\t${0}\nend"

return snippet
