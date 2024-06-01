-- Improve "Bring up specific incident or rumor", "Ask for Directions" and "Ask about Somebody" menus in Adventure mode

--@ module=true

-- requirements
local overlay = require('plugins.overlay')
local utils = require('utils')
local widgets = require('gui.widgets')

-- globals
ignore_words = utils.invert{
    "a", "an", "by", "in", "occurred", "of", "or",
    "s", "the", "this", "to", "was", "which"
}

-- locals
local adventure = df.global.game.main_interface.adventure

AdvRumorsOverlay = defclass(AdvRumorsOverlay, overlay.OverlayWidget)
AdvRumorsOverlay.ATTRS{
    desc='Adds keywords to conversation entries.',
    overlay_only=true,
    default_enabled=true,
    viewscreens='dungeonmode/Conversation',
}

function AdvRumorsOverlay:render()
    rumorUpdate()
end

OVERLAY_WIDGETS = {conversation=AdvRumorsOverlay}

-- CORE FUNCTIONS

-- Converts the choice's print string to a lua string
function choiceToString(choice)
    local line_table = {}
    for i, data in ipairs(choice.print_string.text) do
        table.insert(line_table, dfhack.toSearchNormalized(data.value))
    end
    return table.concat(line_table, "\n")
end

-- Renames the choice's print string based on string, respecting the newlines
function renameChoice(text, choice)
    -- Clear the string
    for i, data in ipairs(choice.print_string.text) do
        df.delete(data)
    end
    choice.print_string.text:resize(0)

    -- Split the string assuming \n is newline
    local line_table = string.split(text, "\n")
    for i, line in ipairs(line_table) do
        -- Create a df string for each line
        local line_ptr = df.new('string')
        line_ptr.value = line
        -- Insert it into the text data
        choice.print_string.text:insert('#', line_ptr)
    end
end

-- Gets the keywords already present on the dialog choice
function getKeywords(choice)
    local keywords = {}
    for i, keyword in ipairs(choice.key_word) do
        table.insert(keywords, keyword.value:lower())
    end
    return keywords
end

-- Adds a keyword to the dialog choice
function addKeyword(choice, keyword)
    local keyword_ptr = df.new('string')
    keyword_ptr.value = keyword
    choice.key_word:insert('#', keyword_ptr)
end

-- Adds multiple keywords to the dialog choice
function addKeywords(choice, keywords)
    for i, keyword in ipairs(keywords) do
        addKeyword(choice, keyword)
    end
end

-- Generates keywords based on the text of the dialog choice, plus keywords for special cases
function generateKeywordsForChoice(choice)
    local new_keywords, keywords_set = {}, utils.invert(getKeywords(choice))

    -- Puts the keyword into a new_keywords table, but only if unique and not ignored
    local function collect_keyword(word)
        if ignore_words[word] or keywords_set[word] then return end
        table.insert(new_keywords, word)
        keywords_set[word] = true
    end

    -- generate keywords from useful words in the text
    for _, data in ipairs(choice.print_string.text) do
        for word in dfhack.toSearchNormalized(data.value):gmatch('%w+') do
            -- collect additional keywords based on the special words
            if word == 'slew' or word == 'slain' then
                collect_keyword('kill')
                collect_keyword('slay')
            elseif word == 'you' or word == 'your' then
                collect_keyword('me')
            end
            -- collect the actual word if it's unique and not ignored
            collect_keyword(word)
        end
    end
    addKeywords(choice, new_keywords)
end

-- Condense the rumor system choices
function rumorUpdate()
    for i, choice in ipairs(adventure.conversation.conv_choice_info) do
        generateKeywordsForChoice(choice)
    end
end
