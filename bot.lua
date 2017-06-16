clr = require "term.colors"
--[[COLORS
  black = "\27[30m",
  blink = "\27[5m",
  blue = "\27[34m",
  bright = "\27[1m",
  clear = "\27[0m",
  cyan = "\27[36m",
  default = "\27[0m",
  dim = "\27[2m",
  green = "\27[32m",
  hidden = "\27[8m",
  magenta = "\27[35m",
  onblack = "\27[40m",
  onblue = "\27[44m",
  oncyan = "\27[46m",
  ongreen = "\27[42m",
  onmagenta = "\27[45m",
  onred = "\27[41m",
  onwhite = "\27[47m",
  onyellow = "\27[43m",
  red = "\27[31m",
  reset = "\27[0m",
  reverse = "\27[7m",
  underscore = "\27[4m",
  white = "\27[37m",
  yellow = "\27[33m"
]]

-- insert master_id and bot_api_key
user = { }
bot = { }
master_id = 41400331
api_errors = {
    [101] = 'Not enough rights to kick participant',
    -- SUPERGROUP: bot is not admin
    [102] = 'USER_ADMIN_INVALID',
    -- SUPERGROUP: trying to kick an admin
    [103] = 'method is available for supergroup chats only',
    -- NORMAL: trying to unban
    [104] = 'Only creator of the group can kick administrators from the group',
    -- NORMAL: trying to kick an admin
    [105] = 'Bad Request: Need to be inviter of the user to kick it from the group',
    -- NORMAL: bot is not an admin or everyone is an admin
    [106] = 'USER_NOT_PARTICIPANT',
    -- NORMAL: trying to kick an user that is not in the group
    [107] = 'CHAT_ADMIN_REQUIRED',
    -- NORMAL: bot is not an admin or everyone is an admin
    [108] = 'there is no administrators in the private chat',
    -- something asked in a private chat with the api methods 2.1

    [110] = 'PEER_ID_INVALID',
    -- user never started the bot
    [111] = 'message is not modified',
    -- the edit message method hasn't modified the message
    [112] = 'Can\'t parse message text: Can\'t find end of the entity starting at byte offset %d+',
    -- the markdown is wrong and breaks the delivery
    [113] = 'group chat is migrated to a supergroup chat',
    -- group updated to supergroup
    [114] = 'Message can\'t be forwarded',
    -- unknown
    [115] = 'Message text is empty',
    -- empty message
    [116] = 'message not found',
    -- message id invalid, I guess
    [117] = 'chat not found',
    -- I don't know
    [118] = 'Message is too long',
    -- over 4096 char
    [119] = 'User not found',
    -- unknown user_id

    [120] = 'Can\'t parse reply keyboard markup JSON object',
    -- keyboard table invalid
    [121] = 'Field \\\"inline_keyboard\\\" of the InlineKeyboardMarkup should be an Array of Arrays',
    -- inline keyboard is not an array of array
    [122] = 'Can\'t parse inline keyboard button: InlineKeyboardButton should be an Object',
    [123] = 'Bad Request: Object expected as reply markup',
    -- empty inline keyboard table
    [124] = 'QUERY_ID_INVALID',
    -- callback query id invalid
    [125] = 'CHANNEL_PRIVATE',
    -- I don't know
    [126] = 'MESSAGE_TOO_LONG',
    -- text of an inline callback answer is too long
    [127] = 'wrong user_id specified',
    -- invalid user_id
    [128] = 'Too big total timeout [%d%.]+',
    -- something about spam an inline keyboards
    [129] = 'BUTTON_DATA_INVALID',
    -- callback_data string invalid

    [130] = 'Type of file to send mismatch',
    -- trying to send a media with the wrong method
    [131] = 'MESSAGE_ID_INVALID',
    -- I don't know
    [132] = 'Can\'t parse inline keyboard button: Can\'t find field "text"',
    -- the text of a button could be nil

    [403] = 'Bot was blocked by the user',
    -- user blocked the bot
    [429] = 'Too many requests: retry later',
    -- the bot is hitting api limits
    [430] = 'Too big total timeout',
    -- too many callback_data requests
}

function bot_init()
    bot = nil
    user = nil
    local file = io.open('bot_api_key.txt', "r")
    if file then
        -- read all contents of file into a string
        bot_api_key = file:read()
        file:close()
    end
    if bot_api_key == '' then
        print(clr.red .. 'API KEY MISSING!' .. clr.reset)
        return
    end
    require("utils")
    require("methods")

    while not bot do
        -- Get bot info and retry if unable to connect.
        local obj = getMe()
        if obj.result then
            bot = obj.result
        end
    end
    while not user do
        -- Get bot info and retry if unable to connect.
        local obj = getChat(master_id)
        if obj.type == 'private' or obj.type == 'user' then
            user = obj
        end
    end
    last_update = last_update or 0
    is_started = true
    print('\n' .. clr.green .. 'BOT RUNNING:\n@' .. bot.username .. '\n' .. bot.first_name .. '\n' .. bot.id .. clr.reset)
    -- whether the bot should be running or not.
end

function adjust_bot(tab)
    tab.type = 'private'
    tab.tg_cli_id = tonumber(tab.id)
    tab.print_name = tab.first_name ..(tab.last_name or '')
    return tab
end

function adjust_user(tab)
    tab.type = 'private'
    tab.tg_cli_id = tonumber(tab.id)
    tab.print_name = tab.first_name ..(tab.last_name or '')
    return tab
end

-- adjust message
-- recursive to simplify code
function adjust_msg(msg)
    -- sender print_name and tg_cli_id
    msg.from = adjust_user(msg.from)
    if msg.chat.type then
        if msg.chat.type == 'private' then
            -- private chat
            msg.bot = adjust_bot(bot)
            msg.chat = adjust_user(msg.chat)
            msg.receiver = 'user#id' .. msg.chat.tg_cli_id
        end
    end
    return msg
end

local function pre_process_reply(msg)
    if msg.reply_to_message then
        msg.reply = true
    end
    return msg
end

-- recursive to simplify code
local function pre_process_forward(msg)
    if msg.forward_from or msg.forward_from_chat then
        msg.forward = true
    end
    if msg.reply then
        msg.reply_to_message = pre_process_forward(msg.reply_to_message)
    end
    return msg
end

-- recursive to simplify code
function pre_process_media_msg(msg)
    msg.media = false
    if msg.audio then
        msg.media = true
        msg.text = "%[audio%]"
        msg.media_type = 'audio'
    elseif msg.contact then
        msg.media = true
        msg.text = "%[contact%]"
        msg.media_type = 'contact'
    elseif msg.document then
        msg.media = true
        msg.text = "%[document%]"
        msg.media_type = 'document'
        if msg.document.mime_type == 'video/mp4' then
            msg.text = "%[gif%]"
            msg.media_type = 'gif'
        end
    elseif msg.location then
        msg.media = true
        msg.text = "%[location%]"
        msg.media_type = 'location'
    elseif msg.photo then
        msg.media = true
        msg.text = "%[photo%]"
        msg.media_type = 'photo'
    elseif msg.sticker then
        msg.media = true
        msg.text = "%[sticker%]"
        msg.media_type = 'sticker'
    elseif msg.video then
        msg.media = true
        msg.text = "%[video%]"
        msg.media_type = 'video'
    elseif msg.voice then
        msg.media = true
        msg.text = "%[voice%]"
        msg.media_type = 'voice'
    end

    if msg.entities then
        for i, entity in pairs(msg.entities) do
            if entity.type == 'url' then
                msg.url = true
                msg.media = true
                msg.media_type = 'link'
                break
            end
        end
        if not msg.url then
            msg.media = false
        end
        -- if the entity it's not an url (username/bot command), set msg.media as false
    end
    return msg
end

function msg_valid(msg)
    if isBlocked(msg.from.id) then
        print(clr.yellow .. 'Not valid: user blocked' .. clr.reset)
        return false
    end
    return true
end

function print_msg(msg)
    if msg then
        if not msg.printed then
            msg.printed = true
            local hour = os.date('%H')
            local minute = os.date('%M')
            local second = os.date('%S')
            local chat_name = msg.chat.title or(msg.chat.first_name ..(msg.chat.last_name or ''))
            local sender_name = msg.from.title or(msg.from.first_name ..(msg.from.last_name or ''))
            local print_text = clr.cyan .. ' [' .. hour .. ':' .. minute .. ':' .. second .. ']  ' .. chat_name .. ' ' .. clr.reset .. clr.red .. sender_name .. clr.reset .. clr.blue .. ' >>> ' .. clr.reset
            if msg.edited then
                print_text = print_text .. clr.blue .. '[edited] ' .. clr.reset
            end
            if msg.forward then
                print_text = print_text .. clr.blue .. '[forward] ' .. clr.reset
            end
            if msg.reply then
                print_text = print_text .. clr.blue .. '[reply] ' .. clr.reset
            end
            if msg.media then
                print_text = print_text .. clr.blue .. '[' ..(msg.media_type or 'unsupported media') .. '] ' .. clr.reset
                if msg.caption then
                    print_text = print_text .. clr.blue .. msg.caption .. clr.reset
                end
            end
            if msg.service then
                if msg.service_type == 'chat_del_user' then
                    print_text = print_text .. clr.red ..(msg.remover.first_name ..(msg.remover.last_name or '')) .. clr.reset .. clr.blue .. ' deleted user ' .. clr.reset .. clr.red ..(msg.removed.first_name ..(msg.removed.last_name or '')) .. ' ' .. clr.reset
                elseif msg.service_type == 'chat_del_user_leave' then
                    print_text = print_text .. clr.red ..(msg.remover.first_name ..(msg.remover.last_name or '')) .. clr.reset .. clr.blue .. ' left the chat ' .. clr.reset
                elseif msg.service_type == 'chat_add_user' then
                    print_text = print_text .. clr.red ..(msg.adder.first_name ..(msg.adder.last_name or '')) .. clr.reset .. clr.blue .. ' added user ' .. clr.reset .. clr.red ..(msg.added.first_name ..(msg.added.last_name or '')) .. ' ' .. clr.reset
                elseif msg.service_type == 'chat_add_user_link' then
                    print_text = print_text .. clr.red ..(msg.adder.first_name ..(msg.adder.last_name or '')) .. clr.reset .. clr.blue .. ' joined chat by invite link ' .. clr.reset
                else
                    print_text = print_text .. clr.blue .. '[' ..(msg.service_type or 'unsupported service') .. '] ' .. clr.reset
                end
            end
            if msg.text then
                print_text = print_text .. clr.blue .. msg.text .. clr.reset
            end
            print(msg.chat.id)
            print(print_text)
        end
    end
end

function check_flood(msg)
    if not msg.edited then
        -- Check flood
        local TIME_CHECK = 2
        local hash = 'reportedbot:user:' .. msg.from.id .. ':msgs'
        local msgs = tonumber(redis:get(hash) or 0)
        local max_msg = 10
        if msgs >= max_msg then
            -- Block user if spammed in private
            blockUser(msg.from.id)
            sendMessage(msg.from.id, 'User ' .. msg.from.id .. ' blocked for spam.\n\n\n\n\n\nIt\'s you shitty asshole.\nBye Bye.')
            sendMessage(user.id, 'User ' .. msg.from.id .. ' blocked for spam.\nPress /unblock' .. msg.from.id .. ' to unblock.')
            return true
        end
        redis:setex(hash, TIME_CHECK, msgs + 1)
    end
    return false
end

-- Returns a table with matches or nil
function match_pattern(pattern, text, lower_case)
    if text then
        local matches = { }
        if lower_case then
            matches = { string.match(text:lower(), pattern) }
        else
            matches = { string.match(text, pattern) }
        end
        if next(matches) then
            return matches
        end
    end
    -- nil
end

function check_command(msg)
    local found = false
    local matches = match_pattern("^[#!/]([Bb][Ll][Oo][Cc][Kk])(.*)", msg.text) or match_pattern("^[#!/]([Bb][Ll][Oo][Cc][Kk])", msg.text)
    if matches then
        if matches[1]:lower() == 'block' then
            found = true
            local success = false
            local this_user = 0
            if msg.reply then
                if msg.reply_to_message.forward then
                    if msg.reply_to_message.forward_from then
                        this_user = msg.reply_to_message.forward_from.id
                        blockUser(this_user)
                        success = true
                    else
                        sendMessage(user.id, 'Can\'t do this to chat.')
                    end
                else
                    sendMessage(user.id, 'No forward found.')
                end
            elseif matches[2] then
                if string.match(matches[2], '^%d+$') then
                    this_user = matches[2]
                    blockUser(this_user)
                    success = true
                elseif string.match(matches[2], '^[^%s]+$') then
                    local obj_user = getChat('@' .. matches[2]:gsub('@', ''))
                    if obj_user then
                        if obj_user.type == 'private' or obj_user.type == 'user' then
                            this_user = obj_user.id
                            blockUser(this_user)
                            success = true
                        end
                    end
                end
            end
            if success then
                sendMessage(user.id, 'User ' .. this_user .. ' blocked.')
                sendMessage(this_user, 'Blocked.')
            end
        end
    end
    local matches = match_pattern("^[#!/]([Uu][Nn][Bb][Ll][Oo][Cc][Kk])(.*)", msg.text) or match_pattern("^[#!/]([Uu][Nn][Bb][Ll][Oo][Cc][Kk])", msg.text)
    if matches then
        if matches[1]:lower() == 'unblock' then
            found = true
            local success = false
            local this_user = 0
            if msg.reply then
                if msg.reply_to_message.forward then
                    if msg.reply_to_message.forward_from then
                        this_user = msg.reply_to_message.forward_from.id
                        unblockUser(this_user)
                        success = true
                    else
                        sendMessage(user.id, 'Can\'t do this to chat.')
                    end
                else
                    sendMessage(user.id, 'No forward found.')
                end
            elseif matches[2] then
                if string.match(matches[2], '^%d+$') then
                    this_user = matches[2]
                    unblockUser(this_user)
                    success = true
                elseif string.match(matches[2], '^[^%s]+$') then
                    local obj_user = getChat('@' .. matches[2]:gsub('@', ''))
                    if obj_user then
                        if obj_user.type == 'private' or obj_user.type == 'user' then
                            this_user = obj_user.id
                            unblockUser(this_user)
                            success = true
                        end
                    end
                end
            end
            if success then
                sendMessage(user.id, 'User ' .. this_user .. ' unblocked.')
                sendMessage(this_user, 'Unblocked.')
            end
        end
    end
    local matches = match_pattern("^[#!/]([Tt][Ee][Ss][Tt][Uu][Ss][Ee][Rr])(.*)", msg.text) or match_pattern("^[#!/]([Tt][Ee][Ss][Tt][Uu][Ss][Ee][Rr])", msg.text)
    if matches then
        if matches[1]:lower() == 'testuser' then
            found = true
            local success = false
            local this_user = 0
            if msg.reply then
                if msg.reply_to_message.forward then
                    if msg.reply_to_message.forward_from then
                        this_user = msg.reply_to_message.forward_from.id
                        if sendChatAction(this_user, 'typing') then
                            success = true
                        else
                            success = false
                        end
                    else
                        sendMessage(user.id, 'Can\'t do this to chat.')
                    end
                else
                    sendMessage(user.id, 'No forward found.')
                end
            elseif matches[2] then
                if string.match(matches[2], '^%d+$') then
                    this_user = matches[2]
                    if sendChatAction(this_user, 'typing') then
                        success = true
                    else
                        success = false
                    end
                elseif string.match(matches[2], '^[^%s]+$') then
                    local obj_user = getChat('@' .. matches[2]:gsub('@', ''))
                    if obj_user then
                        if obj_user.type == 'private' or obj_user.type == 'user' then
                            this_user = obj_user.id
                            if sendChatAction(this_user, 'typing') then
                                success = true
                            else
                                success = false
                            end
                        end
                    end
                end
            end
            if success then
                sendMessage(user.id, 'User ' .. this_user .. ' did not block.')
            else
                sendMessage(user.id, 'User ' .. this_user .. ' blocked the bot.')
            end
        end
    end
    local matches = match_pattern("^[#!/]([Pp][Mm]) (%d+) (.*)", msg.text)
    if matches then
        if matches[1]:lower() == 'pm' then
            found = true
            sendMessage(matches[2], matches[3])
            sendMessage(user.id, 'Text sent.')
        end
    end
    local matches = match_pattern("^[#!/]([Uu][Pp][Dd][Aa][Tt][Ee])", msg.text)
    if matches then
        if matches[1]:lower() == "update" then
            found = true
            sendMessage(user.id, io.popen('git pull'):read('*all'))
        end
    end
    local matches = match_pattern("^[#!/]([Hh][Ee][Ll][Pp])", msg.text)
    if matches then
        if matches[1]:lower() == "help" then
            found = true
            local help_text = '/help: The bot shows this help.\n' ..
            '/update: The bot updates itself from github.\n' ..
            '/pm <chat_id> <text>: The bot writes <text> to <chat_id>.\n' ..
            '/testuser <id>|<username>|<reply_from>: The bot tests whether it has been blocked by the specified user or not.\n' ..
            '/block <id>|<username>|<reply_from>: The bot "blocks" the specified user (you won\'t receive messages anymore from that user).\n' ..
            '/unblock <id>|<username>|<reply_from>: The bot "unblocks" the specified user.'
            sendMessage(user.id, help_text)
        end
    end
    return found
end

-- This function is called when tg receive a msg
function on_msg_receive(msg)
    if not is_started then
        return
    end
    if not msg then
        sendMessage(user.id, 'Loop without message', true)
        return
    end
    if msg.chat.type == 'group' or msg.chat.type == 'supergroup' then
        -- not private message
        return
    end
    msg = pre_process_forward(msg)
    msg = pre_process_reply(msg)
    msg = pre_process_media_msg(msg)
    msg = adjust_msg(msg)
    if msg_valid(msg) then
        if tonumber(msg.from.id) == tonumber(user.id) then
            local command = check_command(msg)
            print(command)
            if not command then
                if msg.reply_to_message then
                    if msg.reply_to_message.forward_from then
                        forwardMessage(msg.reply_to_message.forward_from.id, msg.from.id, msg.message_id)
                        sendChatAction(msg.from.id, 'typing')
                    else
                        sendMessage(user.id, 'Need forward.')
                    end
                else
                    sendMessage(user.id, 'Need reply.')
                end
            end
        else
            if not check_flood(msg) then
                forwardMessage(user.id, msg.from.id, msg.message_id)
                if msg.media then
                    if msg.media_type == 'sticker' then
                        sendMessage(user.id, '↑ STICKER ' .. msg.from.print_name .. ' (' .. msg.from.id .. ') ↑')
                    end
                end
                if msg.forward then
                    if msg.forward_from then
                        if msg.forward_from.id ~= msg.from.id then
                            sendMessage(user.id, '↑ FWD USER ' .. msg.from.print_name .. ' (' .. msg.from.id .. ') ↑')
                        end
                    elseif msg.forward_from_chat then
                        if msg.forward_from_chat.id ~= msg.from.id then
                            sendMessage(user.id, '↑ FWD CHAT ' .. msg.from.print_name .. ' (' .. msg.from.id .. ') ↑')
                        end
                    end
                end
            else
                -- flooder
            end
        end
    end
    print_msg(msg)
end
---------WHEN THE BOT IS STARTED FROM THE TERMINAL, THIS IS THE FIRST FUNCTION HE FOUNDS

bot_init() -- Actually start the script. Run the bot_init function.

while is_started do
    -- Start a loop while the bot should be running.
    local res = getUpdates(last_update + 1)
    -- Get the latest updates!
    if res then
        -- printvardump(res)
        for i, msg in ipairs(res.result) do
            -- Go through every new message.
            if last_update < msg.update_id then
                last_update = msg.update_id
            end
            if msg.edited_message then
                msg.message = msg.edited_message
                msg.message.edited = true
                msg.edited_message = nil
            end
            if msg.message--[[ or msg.callback_query ]] then
                on_msg_receive(msg.message)
            end
        end
    else
        print(clr.red .. 'Connection error' .. clr.reset)
    end
end

print(clr.white .. 'Halted.' .. clr.reset)