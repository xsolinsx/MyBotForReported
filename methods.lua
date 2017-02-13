if not bot_api_key then
    error('You did not set your bot token in bot.lua!')
end

local BASE_URL = 'https://api.telegram.org/bot' .. bot_api_key
local PWR_URL = 'https://api.pwrtelegram.xyz/bot' .. bot_api_key

local curl_context = curl.easy { verbose = false }

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
        error('Incorrect response')
    end

    if code ~= 200 then
        if code == 400 then
            -- error code 400 is general: try to specify
            code = getCode(tab.description)
        end
        print(clr.red .. code, tab.description .. clr.reset)
        sendMessage(user.id, '#BadRequest\n' .. vardumptext(tab) .. '\n' .. code)
        return false, code, tab.description
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