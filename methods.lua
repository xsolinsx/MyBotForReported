if not bot_api_key then
    error('You did not set your bot token in bot.lua!')
end

local BASE_URL = 'https://api.telegram.org/bot' .. bot_api_key
local PWR_URL = 'https://api.pwrtelegram.xyz/bot' .. bot_api_key

local curl_context = curl.easy { verbose = false }
local api_errors = {
    [101] = 'not enough rights to kick/unban chat member',
    -- SUPERGROUP: bot is not admin
    [102] = 'user_admin_invalid',
    -- SUPERGROUP: trying to kick an admin
    [103] = 'method is available for supergroup chats only',
    -- NORMAL: trying to unban
    [104] = 'only creator of the group can kick administrators from the group',
    -- NORMAL: trying to kick an admin
    [105] = 'need to be inviter of the user to kick it from the group',
    -- NORMAL: bot is not an admin or everyone is an admin
    [106] = 'user_not_participant',
    -- NORMAL: trying to kick an user that is not in the group
    [107] = 'chat_admin_required',
    -- NORMAL: bot is not an admin or everyone is an admin
    [108] = 'there is no administrators in the private chat',
    -- something asked in a private chat with the api methods 2.1
    [109] = 'wrong url host',
    -- hyperlink not valid
    [110] = 'peer_id_invalid',
    -- user never started the bot
    [111] = 'message is not modified',
    -- the edit message method hasn't modified the message
    [112] = 'can\'t parse message text: can\'t find end of the entity starting at byte offset %d+',
    -- the markdown is wrong and breaks the delivery
    [113] = 'group chat is migrated to a supergroup chat',
    -- group updated to supergroup
    [114] = 'message can\'t be forwarded',
    -- unknown
    [115] = 'message text is empty',
    -- empty message
    [116] = 'message not found',
    -- message id invalid, I guess
    [117] = 'chat not found',
    -- I don't know
    [118] = 'message is too long',
    -- over 4096 char
    [119] = 'user not found',
    -- unknown user_id
    [120] = 'can\'t parse reply keyboard markup json object',
    -- keyboard table invalid
    [121] = 'field \\\"inline_keyboard\\\" of the inlinekeyboardmarkup should be an array of arrays',
    -- inline keyboard is not an array of array
    [122] = 'can\'t parse inline keyboard button: inlinekeyboardbutton should be an object',
    [123] = 'bad Request: object expected as reply markup',
    -- empty inline keyboard table
    [124] = 'query_id_invalid',
    -- callback query id invalid
    [125] = 'channel_private',
    -- I don't know
    [126] = 'message_too_long',
    -- text of an inline callback answer is too long
    [127] = 'wrong user_id specified',
    -- invalid user_id
    [128] = 'too big total timeout [%d%.]+',
    -- something about spam an inline keyboards
    [129] = 'button_data_invalid',
    -- callback_data string invalid
    [130] = 'type of file to send mismatch',
    -- trying to send a media with the wrong method
    [131] = 'message_id_invalid',
    -- I don't know. Probably passing a string as message id
    [132] = 'can\'t parse inline keyboard button: can\'t find field "text"',
    -- the text of a button could be nil
    [133] = 'can\'t parse inline keyboard button: field "text" must be of type String',
    [134] = 'user_id_invalid',
    [135] = 'chat_invalid',
    [136] = 'user_deactivated',
    -- deleted account, probably
    [137] = 'can\'t parse inline keyboard button: text buttons are unallowed in the inline keyboard',
    [138] = 'message was not forwarded',
    [139] = 'can\'t parse inline keyboard button: field \\\"text\\\" must be of type string',
    -- "text" field in a button object is not a string
    [140] = 'channel invalid',
    -- /shrug
    [141] = 'wrong message entity: unsupproted url protocol',
    -- username in an inline link [word](@username) (only?)
    [142] = 'wrong message entity: url host is empty',
    -- inline link without link [word]()
    [143] = 'there is no photo in the request',
    [144] = 'can\'t parse message text: unsupported start tag "%w+" at byte offset %d+',
    [145] = 'can\'t parse message text: expected end tag at byte offset %d+',
    [146] = 'button_url_invalid',
    -- invalid url (inline buttons)
    [147] = 'message must be non%-empty',
    -- example: ```   ```
    [148] = 'can\'t parse message text: unmatched end tag at byte offset',
    [149] = 'reply_markup_invalid',
    -- returned while trying to send an url button without text and with an invalid url
    [150] = 'message text must be encoded in utf%-8',
    [151] = 'url host is empty',
    [152] = 'requested data is unaccessible',
    -- the request involves a private channel and the bot is not admin there
    [153] = 'unsupported url protocol',
    [154] = 'can\'t parse message text: unexpected end tag at byte offset %d+',
    [155] = 'message to edit not found',
    [156] = 'group chat was migrated to a supergroup chat',
    [157] = 'message to forward not found',
    [403] = 'bot was blocked by the user',
    -- user blocked the bot
    [429] = 'Too many requests: retry later',
    -- the bot is hitting api limits
    [430] = 'Too big total timeout',
    -- too many callback_data requests
}

local function performRequest(url)
    local data = { }

    -- if multithreading is made, this request must be in critical section
    local c = curl_context:setopt_url(url):setopt_writefunction(table.insert, data):perform()

    return table.concat(data), c:getinfo_response_code()
end

function saveUsername(obj, chat_id)
    if obj then
        if type(obj) == 'table' then
            if obj.username then
                redis:hset('bot:usernames', '@' .. obj.username:lower(), obj.id)
                if obj.type ~= 'bot' and obj.type ~= 'private' and obj.type ~= 'user' then
                    if chat_id then
                        redis:hset('bot:usernames:' .. chat_id, '@' .. obj.username:lower(), obj.id)
                    end
                end
            end
        end
    end
end

-- *** START API FUNCTIONS ***
function sendRequest(url)
    local dat, code = performRequest(url)
    local tab = JSON.decode(dat)

    if not tab then
        print(clr.red .. 'Error while parsing JSON' .. clr.reset, code)
        print(clr.yellow .. 'Data:' .. clr.reset, dat)
        sendMessage(user.id, dat .. "\n" .. code)
    end

    if code ~= 200 then
        if code == 400 then
            -- error code 400 is general: try to specify
            code = getCode(tab.description)
        end

        print(clr.red .. code, tab.description .. clr.reset)
        sendMessage(user.id, '#BadRequest\n' .. vardumptext(tab) .. '\n' .. code)

        local retry_after
        if code == 429 then
            retry_after = tab.parameters.retry_after
            print(('%sRate limited for %d seconds%s'):format(clr.yellow, retry_after, clr.reset))
        end
        return nil, code, tab.description, retry_after
    end

    if not tab.ok then
        sendMessage(user.id, 'Not tab.ok' .. vardumptext(tab))
        return false, tab.description
    end

    return tab
end

function getMe()
    local url = BASE_URL .. '/getMe'
    return sendRequest(url)
end

function getUpdates(offset)
    local url = BASE_URL .. '/getUpdates?timeout=20'
    if offset then
        url = url .. '&offset=' .. offset
    end
    return sendRequest(url)
end

function APIgetChat(id_or_username)
    local url = BASE_URL .. '/getChat?chat_id=' .. id_or_username
    return sendRequest(url)
end

function getCode(error)
    for k, v in pairs(api_errors) do
        if error:match(v) then
            return k
        end
    end
    -- error unknown
    return 7
end

function sendMessage(chat_id, text, use_markdown, reply_to_message_id, send_sound)
    -- print(text)
    local obj = getChat(chat_id, true)
    if type(obj) == 'table' then
        if text then
            if type(text) ~= 'table' then
                if text ~= '' then
                    local text_max = 4096
                    local text_len = string.len(text)
                    local num_msg = math.ceil(text_len / text_max)
                    local url = BASE_URL ..
                    '/sendMessage?chat_id=' .. chat_id ..
                    '&disable_web_page_preview=true'
                    local reply = false
                    if reply_to_message_id then
                        url = url .. '&reply_to_message_id=' .. reply_to_message_id
                        reply = true
                    end
                    if use_markdown then
                        url = url .. '&parse_mode=Markdown'
                    end
                    if not send_sound then
                        url = url .. '&disable_notification=true'
                        -- messages are silent by default
                    end

                    if num_msg <= 1 then
                        url = url .. '&text=' .. URL.escape(text)

                        local res, code = sendRequest(url)

                        if not res and code then
                            -- if the request failed and a code is returned (not 403 and 429)
                            if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                                sendMessage(user.id, 'send_msg', code .. '\n' .. text)
                            end
                        end
                        local sent_msg = { from = bot, chat = obj, text = text, reply = reply }
                        print_msg(sent_msg)
                    else
                        local my_text = string.sub(text, 1, 4096)
                        local rest = string.sub(text, 4096, text_len)
                        url = url .. '&text=' .. URL.escape(my_text)

                        local res, code = sendRequest(url)

                        if not res and code then
                            -- if the request failed and a code is returned (not 403 and 429)
                            if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                                sendMessage(user.id, 'send_msg', code .. '\n' .. text)
                            end
                        end
                        local sent_msg = { from = bot, chat = obj, text = my_text, reply = reply }
                        print_msg(sent_msg)
                        res, code = sendMessage(chat_id, rest, use_markdown, reply_to_message_id, send_sound)
                    end

                    return res, code
                    -- return false, and the code
                end
            end
        end
    end
end

function forwardMessage(chat_id, from_chat_id, message_id)
    local obj_from = getChat(from_chat_id, true)
    local obj_to = getChat(chat_id, true)
    if type(obj_from) == 'table' and type(obj_to) == 'table' then
        local url = BASE_URL ..
        '/forwardMessage?chat_id=' .. chat_id ..
        '&from_chat_id=' .. from_chat_id ..
        '&message_id=' .. message_id
        local sent_msg = { from = bot, chat = obj_to, text = text, forward = true }
        print_msg(sent_msg)
        return sendRequest(url)
    end
end

function editMessageText(chat_id, message_id, text, keyboard, markdown)
    local url = BASE_URL ..
    '/editMessageText?chat_id=' .. chat_id ..
    '&message_id=' .. message_id ..
    '&text=' .. URL.escape(text)
    if markdown then
        url = url .. '&parse_mode=Markdown'
    end
    url = url .. '&disable_web_page_preview=true'
    if keyboard then
        url = url .. '&reply_markup=' .. JSON.encode(keyboard)
    end
    local res, code = sendRequest(url)

    if not res and code then
        -- if the request failed and a code is returned (not 403 and 429)
        if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
            sendMessage(user.id, 'send_msg', code .. '\n' .. text)
        end
    end

    return res, code
    -- return false, and the code
end

function sendChatAction(chat_id, action)
    -- Support actions are typing, upload_photo, record_video, upload_video, record_audio, upload_audio, upload_document, find_location, record_videonote, upload_videonote
    local url = BASE_URL ..
    '/sendChatAction?chat_id=' .. chat_id ..
    '&action=' .. action
    return sendRequest(url)
end
-- *** END API FUNCTIONS ***

-- *** START PWRTELEGRAM API FUNCTIONS ***
function resolveChat(id_or_username)
    local url = PWR_URL .. '/getChat?chat_id=' .. id_or_username
    local dat, code = HTTPS.request(url)

    if not dat then
        return false, code
    end

    local tab = JSON.decode(dat)

    if code ~= 200 then
        if not tab then
            return false
        else
            sendMessage(user.id, '#BadRequest PWRTelegram API\n' .. vardumptext(tab) .. '\n' .. code)
            return false
        end
    end

    return tab
end
-- *** END PWRTELEGRAM API FUNCTIONS ***

function getChat(id_or_username, force_api)
    local obj = nil
    --[[if pwr_get_chat and not force_api then
        obj = resolveChat(id_or_username)
        if obj.result then
            obj = obj.result
        end
    else]]
    local ok = false
    if not ok then
        local hash = 'bot:usernames'
        local stored = nil
        if type(id_or_username) == 'string' then
            stored = redis:hget(hash, id_or_username:lower())
        else
            stored = redis:hget(hash, id_or_username)
        end
        if stored then
            obj = APIgetChat(stored)
            if type(obj) == 'table' then
                if obj.result then
                    obj = obj.result
                    ok = true
                    saveUsername(obj)
                end
            end
        end
    end
    if not ok then
        obj = APIgetChat(id_or_username)
        if type(obj) == 'table' then
            if obj.result then
                obj = obj.result
                ok = true
            end
        end
    end
    if not ok then
        obj = resolveChat(id_or_username)
        if type(obj) == 'table' then
            if obj.result then
                obj = obj.result
                ok = true
                saveUsername(obj)
            end
        end
    end
    -- end
    if ok then
        return obj
    end
    return nil
end

function blockUser(user_id)
    if user_id ~= user.id then
        redis:sadd('reportedbot:blocked', user_id)
        return 'User Blocked.'
    else
        return 'Can\'t block yourself.'
    end
end

function unblockUser(user_id)
    redis:srem('reportedbot:blocked', user_id)
    return 'User Unblocked.'
end

function isBlocked(user_id)
    if redis:sismember('reportedbot:blocked', user_id) then
        return true
    else
        return false
    end
end