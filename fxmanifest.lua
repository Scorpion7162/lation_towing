
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'iamlation'
description 'An advanced tow truck resource designed for ESX/QBCore/Qbox with a focus on performance and ease of use.'
version '2.0.0'

client_scripts {
    'client/*.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/*.lua'
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}