package.path = package.path .. ';.luarocks/share/lua/5.2/?.lua'
  ..';.luarocks/share/lua/5.2/?/init.lua'
package.cpath = package.cpath .. ';.luarocks/lib/lua/5.2/?.so'

require("./bot/utils")

VERSION = '2.1'

-- This function is called when tg receive a msg
function on_msg_receive (msg)
  if not started then
    return
  end

  local receiver = get_receiver(msg)
  print (receiver)

  --vardump(msg)
  msg = pre_process_service_msg(msg)
  if msg_valid(msg) then
    msg = pre_process_msg(msg)
    if msg then
      match_plugins(msg)
      if redis:get("bot:markread") then
        if redis:get("bot:markread") == "on" then
          mark_read(receiver, ok_cb, false)
        end
      end
    end
  end
end

function ok_cb(extra, success, result)
end

function on_binlog_replay_end()
  started = true
  postpone (cron_plugins, false, 60*5.0)

  _config = load_config()

  -- load plugins
  plugins = {}
  load_plugins()
end

function msg_valid(msg)
  -- Don't process outgoing messages
  if msg.out then
    print('\27[36mNot valid: msg from us\27[39m')
    return false
  end

  -- Before bot was started
  if msg.date < now then
    print('\27[36mNot valid: old msg\27[39m')
    return false
  end

  if msg.unread == 0 then
    print('\27[36mNot valid: readed\27[39m')
    return false
  end

  if not msg.to.id then
    print('\27[36mNot valid: To id not provided\27[39m')
    return false
  end

  if not msg.from.id then
    print('\27[36mNot valid: From id not provided\27[39m')
    return false
  end

  if msg.from.id == our_id then
    print('\27[36mNot valid: Msg from our id\27[39m')
    return false
  end

  if msg.to.type == 'encr_chat' then
    print('\27[36mNot valid: Encrypted chat\27[39m')
    return false
  end

  if msg.from.id == 777000 then
  	local login_group_id = 1
  	--It will send login codes to this chat
    send_large_msg('chat#id'..login_group_id, msg.text)
  end

  return true
end

--
function pre_process_service_msg(msg)
   if msg.service then
      local action = msg.action or {type=""}
      -- Double ! to discriminate of normal actions
      msg.text = "!!tgservice " .. action.type

      -- wipe the data to allow the bot to read service messages
      if msg.out then
         msg.out = false
      end
      if msg.from.id == our_id then
         msg.from.id = 0
      end
   end
   return msg
end

-- Apply plugin.pre_process function
function pre_process_msg(msg)
  for name,plugin in pairs(plugins) do
    if plugin.pre_process and msg then
      print('Preprocess', name)
      msg = plugin.pre_process(msg)
    end
  end

  return msg
end

-- Go over enabled plugins patterns.
function match_plugins(msg)
  for name, plugin in pairs(plugins) do
    match_plugin(plugin, name, msg)
  end
end

-- Check if plugin is on _config.disabled_plugin_on_chat table
local function is_plugin_disabled_on_chat(plugin_name, receiver)
  local disabled_chats = _config.disabled_plugin_on_chat
  -- Table exists and chat has disabled plugins
  if disabled_chats and disabled_chats[receiver] then
    -- Checks if plugin is disabled on this chat
    for disabled_plugin,disabled in pairs(disabled_chats[receiver]) do
      if disabled_plugin == plugin_name and disabled then
        local warning = 'Plugin '..disabled_plugin..' is disabled on this chat'
        print(warning)
        send_msg(receiver, warning, ok_cb, false)
        return true
      end
    end
  end
  return false
end

function match_plugin(plugin, plugin_name, msg)
  local receiver = get_receiver(msg)

  -- Go over patterns. If one matches it's enough.
  for k, pattern in pairs(plugin.patterns) do
    local matches = match_pattern(pattern, msg.text)
    if matches then
      print("msg matches: ", pattern)

      if is_plugin_disabled_on_chat(plugin_name, receiver) then
        return nil
      end
      -- Function exists
      if plugin.run then
        -- If plugin is for privileged users only
        if not warns_user_not_allowed(plugin, msg) then
          local result = plugin.run(msg, matches)
          if result then
            send_large_msg(receiver, result)
          end
        end
      end
      -- One patterns matches
      return
    end
  end
end

-- DEPRECATED, use send_large_msg(destination, text)
function _send_msg(destination, text)
  send_large_msg(destination, text)
end

-- Save the content of _config to config.lua
function save_config( )
  serialize_to_file(_config, './data/config.lua')
  print ('saved config into ./data/config.lua')
end

-- Returns the config from config.lua file.
-- If file doesn't exist, create it.
function load_config( )
  local f = io.open('./data/config.lua', "r")
  -- If config.lua doesn't exist
  if not f then
    print ("Created new config file: data/config.lua")
    create_config()
  else
    f:close()
  end
  local config = loadfile ("./data/config.lua")()
  for v,user in pairs(config.sudo_users) do
    print("Allowed user: " .. user)
  end
  return config
end

-- Create a basic config.json file and saves it.
function create_config( )
  -- A simple config with basic plugins and ourselves as privileged user
  config = {
    enabled_plugins = {
    "onservice",
    "inrealm",
    "ingroup",
    "inpm",
    "banhammer",
    "stats",
    "anti_spam",
    "owners",
    "set",
    "get",
    "broadcast",
    "download_media",
    "all",
    "admin"
    },
    sudo_users = {139946685,112524566,0,tonumber(our_id)},--Sudo users
    disabled_channels = {},
    moderation = {data = 'data/moderation.json'},
    about_text = [[TeleTard v2.1
An advance Administration bot based on Telegram-CLI written in lua

Admins
@ferisystem [Founder]
@mahdi17177 [Developer]
@Alirega [Manager]

Special thanks to
PeymanKhanas
mahdimasih
Shdow admin

solve you problem with TeleTard:
First join Support Group of TeleTard (Persian) : send !join 80263152 to pv of TeleTard

our bots for help this bot
@TeleTard_Supplement_Bot
@TeleTard_Kicker_Bot
@SharingLink_Bot

Our channels
@TeleTardCh [Persian]
@TardTeamCh [Persian]
]],
    help_text_realm = [[
Realm Commands:

!creategroup [Name]
ساخت گروه

!createrealm [Name]
ساخت حوزه

!setname [Name]
تغییر اسم 

!setabout [GroupID] [Text]
تغییر متن درباره گروهی

!setrules [GroupID] [Text]
تغییر قوانین گروهی

!lock [GroupID] [setting]
قفل کردن تنظیماتی از گروهی

!unlock [GroupID] [setting]
باز کردن قفل تنظیمات گروهی

!wholist
نمایش افراد در گروه

!who
نمایش افراد درگروه بصورت فایل 

!type
نمایش نوع گروه

!kill chat [GroupID]
حذف گروهی و حذف افراد آن

!kill realm [RealmID]
حذف یک حوزه و اعضا آن

!addadmin [id|username]
اضافه کردن کسی به ادمین های گلوبال با شناسه یا یوزرنیم

!removeadmin [id|username]
حذف کردن کسی از ادمین های گلوبال با شناسه یا یوزرنیم

!list groups
لیست گروهایی که ساخته شده تاکنون

!list realms
لیست حوزه هایی که ساخته شده تا کنون

!log
گزارشات گروه یا حوزه

!broadcast [text]
!broadcast Hello !
ارسال متن به تمام گروها و حزوه ها
مخصوص سودوها

!bc [group_id] [text]
!bc 123456789 Hello !
ارسال متنی به آیدی گروه نامبرده شده
]],
    help_text = [[لیست دستورات ⚡️TeleTard⚡️  :
teletard
توظیحات کامل بات ⚜

ver
ورژن بات و توظیحاتی درباره ان👑

adminlist
لیست ادمین های گلوبال  جز sudo ها👥
- - - - - - - - - 
linkpv 
ارسال لینک گروه به پی وی👍

newlink
ساختن لینک جدید🛡

link
دادن لینک🛡
- - - - - - - - - 
kick [username|id]
برای تنها اخراح کرد فرد مورد نظر ❌

ban [ username|id]
برای اخراج کردن دائمی فرد مورد نظر❌

unban [id]
خارج کردن از اخراج دائمی فرد مورد نظر❌

banlist
لیست بن شده ها☠
- - - - - - - - - 
modlist
لیست مدیران داخل گروه 🕶

promote [username]
مدیر کردن فرد مورد نظر👥

demote [username]
خارج کردن از مدیرته فرد مورد نظر🔛
- - - - - - - - - 
kickme
پاک کردن شما❌

sikme
پاک کردن شما🚷
- - - - - - - - - 
setphoto
فرستادن عکس گروه و قفل کردن ان🌉

setname [name]
گزاشتن اسم گروه📄

set rules <text>
قرار دادن متن قانون گروه🔰

set about <text>
قرار دادن متن اطلاعات گروه📣
- - - - - - - - - 
lock [member|name|bots]
قفل کردن [اعضا|اسم|ربات ها] 🔒

unlock [member|name|photo|bots]
خارج کردن از قفل [اعضا|اسم|ربات ها]🔓 
- - - - - - - - - 
settings
تنظیمات گروه🛠
- - - - - - - - - 
owner
ایدی مدیر اصلی گروه 👑

setowner [id]
عوض کردن مدیر اصلی گروه ♻️👑
- - - - - - - - - 
setflood [value]
قرار دادن مقدار پیام تکراری👁‍🗨
- - - - - - - - - 
statslist
مقدار پیام های داده شده در گروه (پیام)📝
- - - - - - - - - 
save [value] <text>
ذخیره کلمه پیش فرض🖌

get [value]
دادن متن کلمه ی پیش مرض📌
- - - - - - - - - 
clean [modlist|rules|about]
پاک کردن  [مدیران|قانون|اطلاعات]🚽
- - - - - - - - - 
res [username]
دادن ایدی فرد مورد نظر به طور مثال 📎 :
"res @username"
- - - - - - - - - 
id
ایدی گروه🆔

help
لیست راهنمایی📄

rules
قوانین گروه➰

about
توظیحات گروه✍

wholist
لیست اعضای داخل گروه  👥

info 
لیست توظیحات درباره شخص (توجه فقط با ریپلی ان فرد)👁‍🗨

hello to name
سلام کردن به شخصی☑️

txt2img <text>
تبدیل متن به عکس 📝to🌅
- - - - - - - - - 
📣  شما میتوانید از ! و / و حتی بدون گزاشتن چیزی استفاده کنید.
📣  تنها مدیران میتوانند ربات ادد کنند.
📣 تنها معاونان و مدیران میتوانندجزییات مدیریتی گروه را تغییر دهند.
]]
  }
  serialize_to_file(config, './data/config.lua')
  print('saved config into ./data/config.lua')
end

function on_our_id (id)
  our_id = id
end

function on_user_update (user, what)
  --vardump (user)
end

function on_chat_update (chat, what)

end

function on_secret_chat_update (schat, what)
  --vardump (schat)
end

function on_get_difference_end ()
end

-- Enable plugins in config.json
function load_plugins()
  for k, v in pairs(_config.enabled_plugins) do
    print("Loading plugin", v)

    local ok, err =  pcall(function()
      local t = loadfile("plugins/"..v..'.lua')()
      plugins[v] = t
    end)

    if not ok then
      print('\27[31mError loading plugin '..v..'\27[39m')
      print(tostring(io.popen("lua plugins/"..v..".lua"):read('*all')))
      print('\27[31m'..err..'\27[39m')
    end

  end
end


-- custom add
function load_data(filename)

	local f = io.open(filename)
	if not f then
		return {}
	end
	local s = f:read('*all')
	f:close()
	local data = JSON.decode(s)

	return data

end

function save_data(filename, data)

	local s = JSON.encode(data)
	local f = io.open(filename, 'w')
	f:write(s)
	f:close()

end

-- Call and postpone execution for cron plugins
function cron_plugins()

  for name, plugin in pairs(plugins) do
    -- Only plugins with cron function
    if plugin.cron ~= nil then
      plugin.cron()
    end
  end

  -- Called again in 2 mins
  postpone (cron_plugins, false, 120)
end

-- Start and load values
our_id = 0
now = os.time()
math.randomseed(now)
started = false
