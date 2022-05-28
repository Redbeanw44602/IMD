package.path = package.path..';.\\share\\?.lua'
package.cpath = package.cpath..';.\\lib\\?.dll'

local Fs = require "filesystem"
local curl = require "cURL"
local JSON = require "dkjson"
require "logger"
require "native-type-helper"

os.execute('chcp 65001 > nul')

local mLog = Logger:new('IMD')
local gl_using_cookie = ''

----------------------------------

mLog:Info('请问您想要下载什么平台的音乐？')
mLog:Info('1. 网易云音乐')
mLog:Info('2. QQ音乐')
mLog:Info('3. 酷我音乐')

io.write('(1-3) > ')
local switched_music_platform = io.read()

----------------------------------

function ExecPf(t)
    t.login()

    mLog:Info('请问具体需要下载什么？')
    mLog:Info('1. 单曲')
    mLog:Info('2. 歌单')

    io.write('(1-2) > ')
    local chosed_download_what = io.read()
    if chosed_download_what ~= '1' and chosed_download_what ~= '2' then
        mLog:Error('输入有误！')
        return
    end

    t.use(chosed_download_what)
end

function HttpGet(url,wfunc,needStat)
    local tmp = ''
    local wtfunc = wfunc or function (cont)
        tmp = tmp .. cont
    end
    needStat = needStat or 200
    local request = curl.easy {
        url = url,
        httpheader = {
            'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9',
            'Accept-Language: zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
            'Cache-Control: no-cache',
            'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/99.0.4844.51 Safari/537.36 Edg/99.0.1150.39'
        },
        accept_encoding = 'gzip, deflate, br',
        ssl_verifypeer = false,
        ssl_verifyhost = false,
        writefunction = wtfunc
    }
    request:perform()
    if request:getinfo_response_code() ~= needStat then
        return nil
    end
    if needStat == 301 or needStat == 302 then
        return HttpGet(request:getinfo_redirect_url(),wfunc)
    end
    request:close()
    if not wfunc then
        return tmp
    end
    return 1
end

NeteaseMusic = {
    ApiAddr = 'https://music-netease.amd.rocks',
    use = function (dw)
        local sLog = Logger:new('Netease')
        if dw == '1' then
            sLog:Info('请输入单曲ID，如有多首请用逗号分割：')
            io.write('(n) > ')
            local need_download_ids = io.read()
            string.gsub(need_download_ids,'，',',')
            local details = HttpGet(string.format('%s/song/detail?ids=%s&cookie=%s',NeteaseMusic.ApiAddr,need_download_ids,gl_using_cookie))
            if not details then
                mLog:Error('HttpGet 失败！')
                return
            end
            details = JSON.decode(details)
            if not details.songs then
                mLog:Error('解析 detail 失败！')
                return
            end
            NeteaseMusic.printMusicDetails(details,NeteaseMusic.get_music)
        elseif dw == '2' then
            local playlist_id = 0
            if gl_using_cookie ~= '' then
                sLog:Info('选择一个歌单，也可以输入歌单ID：')
                local uid = JSON.decode(HttpGet(string.format('%s/login/status?cookie=%s',NeteaseMusic.ApiAddr,gl_using_cookie))).data.account.id
                local playlists = HttpGet(string.format('%s/user/playlist?uid=%s&cookie=%s',NeteaseMusic.ApiAddr,uid,gl_using_cookie))
                playlists = JSON.decode(playlists)
                if not playlists then
                    sLog:Error('playlist 解析失败！')
                    return
                end
                sLog:Info('0. 手动输入')
                for k,v in pairs(playlists.playlist) do
                    sLog:Info('%s. %s',k,v.name)
                end
                io.write(string.format('(0-%s) > ',#playlists.playlist))
                local chose_what = tonumber(io.read())
                if chose_what == 0 then
                    io.write('(n) > ')
                    playlist_id = tonumber(io.read())
                else
                    playlist_id = playlists.playlist[chose_what].id
                end
            else
                sLog:Info('请输入需要下载的歌单ID：')
                io.write('(n) > ')
                playlist_id = tonumber(io.read())
            end
            local playlist_detail = HttpGet(string.format('%s/playlist/detail?id=%s&cookie=%s',NeteaseMusic.ApiAddr,playlist_id,gl_using_cookie))
            playlist_detail = JSON.decode(playlist_detail)
            if not playlist_detail then
                sLog:Error('playlist 解析失败！')
                return
            end
            if playlist_detail.code == 200 then
                sLog:Info('歌单已选定，名称：%s',playlist_detail.playlist.name)
            else
                sLog:Info('获取歌单信息失败')
                return
            end
            local list = HttpGet(string.format('%s/playlist/track/all?id=%s&cookie=%s',NeteaseMusic.ApiAddr,playlist_id,gl_using_cookie))
            list = JSON.decode(list)
            if not list then
                sLog:Error('playlist 解析失败！')
                return
            end
            NeteaseMusic.printMusicDetails(list,NeteaseMusic.get_music)
        end
    end,
    login = function ()
        local pLog = Logger:new('Login')
        local suffix = 'netease'
        local cookies = {}
        for n,name in pairs(Fs:getDirectoryList('cookies')) do
            local a = string.sub(name,string.len('cookies\\')+1)
            if string.sub(a,-1*string.len('.'..suffix)) == '.'..suffix then
                cookies[#cookies+1] = string.gsub(a,'.netease','')
            end
        end
        pLog:Info('是否需要登录？')
        pLog:Info('0. 不使用')
        for n,cookiename in pairs(cookies) do
            pLog:Info('%s. 使用 %s 的 cookie',n,cookiename)
        end

        io.write(string.format('(0-%s) > ',#cookies))
        local use_who_cookie = io.read()
        use_who_cookie = tonumber(use_who_cookie)
        if use_who_cookie == 0 then
            return
        end

        local cookie = Fs:readFrom(string.format('cookies/%s.%s',cookies[use_who_cookie],suffix))
        pLog:Info('正在检查登录...')
        local login = HttpGet(string.format('%s/login/status?cookie=%s',NeteaseMusic.ApiAddr,cookie))
        if not login then
            mLog:Error('HttpGet失败！')
        end

        login = JSON.decode(login)
        if not login then
            mLog:Error('login 解析失败！')
            return
        end

        if login.data.profile == nil then
            pLog:Error('登录失败')
            return
        else
            pLog:Info('登录成功，欢迎 %s 回来。',login.data.profile.nickname)
            gl_using_cookie = cookie
        end

    end,
    get_music = function (music)
        local pLog = Logger:new('Download')

        --- down_music - method A:
        local result = HttpGet(string.format('%s/song/url?id=%s&cookie=%s',NeteaseMusic.ApiAddr,music.id,gl_using_cookie))
        result = JSON.decode(result)
        if result and result.data[1].url then
            local music_file = Fs:open(string.format('download/%s.%s',music.name,result.data[1].encodeType),'w+b')
            pLog:Info('正在下载歌曲 > %s ...',result.data[1].encodeType)
            local stat = HttpGet(result.data[1].url,music_file)
            music_file:close()
            if stat then
                NeteaseMusic.get_lrc(music)
                return
            end
        end
        pLog:Warn('音乐下载失败，正在尝试方法B ...')

        --- down_music - method B:
        pLog:Info('正在下载歌曲 > mp3 ...')
        local music_file = Fs:open(string.format('download/%s.mp3',music.name),'w+b')
        local stat = HttpGet(string.format('https://music.163.com/song/media/outer/url?id=%s.mp3',music.id),music_file,302)
        music_file:close()
        if not stat then
            pLog:Error('音乐下载失败。')
            return
        else
            NeteaseMusic.get_lrc(music)
        end

    end,
    get_lrc = function (music)
        local pLog = Logger:new('Download')

        pLog:Info('正在下载歌词 > lrc ...')
        local result = HttpGet(string.format('%s/lyric/?id=%s',NeteaseMusic.ApiAddr,music.id))
        result = JSON.decode(result)
        if not result then
            pLog:Error('lrc 解析失败！')
            return
        end
        if not result.lrc or not result.lrc.lyric then
            pLog:Warn('该歌曲没有歌词')
            return
        end
        Fs:writeTo(string.format('download/%s.lrc',music.name),result.lrc.lyric)
    end,
    printMusicDetails = function (details,callback)
        local pLog = Logger:new('Detail')
        local function getStr_singerlist(list)
            local rtn = ''
            for k,v in pairs(list) do
                rtn = rtn .. v.name .. ', '
            end
            return string.sub(rtn,0,string.len(rtn)-2)
        end
        local function getStr_feestat(stat)
            if stat == 0 then
                return '免费'
            elseif stat == 1 then
                return 'VIP歌曲'
            elseif stat == 4 then
                return '需要购买专辑'
            elseif stat == 8 then
                return '非会员低音质'
            end
        end
        local function getStr_timelong(dt)
            local a = {math.modf(dt/1000/60)}
            return string.format('%s分%s秒',a[1],math.floor(60*a[2]))
        end
        local function getStr_coverType(ct)
            if ct == 1 then
                return '原曲'
            elseif ct == 2 then
                return '翻唱'
            else
                return '未知'
            end
        end
        local function getStr_copyright(n)
            if n then
                return '无'
            else
                return '有'
            end
        end
        for key,cont in pairs(details.songs) do
            pLog:Info('')
            pLog:Info('—[%s]——————————————————————————',key)
            pLog:Info('名称：%s',cont.name)
            pLog:Info('歌手：%s',getStr_singerlist(cont.ar))
            pLog:Info('限制情况：%s',getStr_feestat(cont.fee))
            pLog:Info('时长：%s',getStr_timelong(cont.dt))
            pLog:Info('类型：%s',getStr_coverType(cont.originCoverType))
            pLog:Info('版权：%s',getStr_copyright(cont.noCopyrightRcmd))
            pLog:Info('')
            callback {
                id = cont.id,
                name = string.delete(cont.name,'\\','/',':','?','*','"','<','>','|')
            }
        end
    end
}

QQMusic = {
    ApiAddr = '',
    use = function ()
        local sLog = Logger:new('QQ')
    end,
    login = function ()
        
    end
}

KuwoMusic = {
    ApiAddr = 'https://music-kuwo.amd.rocks',
    use = function ()
        local sLog = Logger:new('Kuwo')
    end
}

if switched_music_platform == '1' then
    ExecPf(NeteaseMusic)
elseif switched_music_platform == '2' then
    ExecPf(QQMusic)
elseif switched_music_platform == '3' then
    ExecPf(KuwoMusic)
else
    mLog:Error('输入错误！')
    return
end