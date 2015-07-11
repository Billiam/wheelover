package.preload['love-update.vendor.luajit-request'] = (function (...)
  --[[
  LuaJIT-Request
  Lucien Greathouse
  Wrapper for LuaJIT-cURL for easy HTTP(S) requests.
  
  Copyright (c) 2014 lucien Greathouse
  
  This software is provided 'as-is', without any express
  or implied warranty. In no event will the authors be held
  liable for any damages arising from the use of this software.
  
  Permission is granted to anyone to use this software for any purpose,
  including commercial applications, andto alter it and redistribute it
  freely, subject to the following restrictions:
  
  1. The origin of this software must not be misrepresented; you must not
  claim that you wrote the original software. If you use this software
  in a product, an acknowledgment in the product documentation would be
  appreciated but is not required.
  
  2. Altered source versions must be plainly marked as such, and must
  not be misrepresented as being the original software.
  
  3. This notice may not be removed or altered from any source distribution.
  ]]

  local path = (...):gsub("%.init$", ""):match("%.?(.-)$") .. "."

  local ffi = require("ffi")
  local curl = require(path .. "luajit-curl")
  local request

  local function url_encode(str)
    if (str) then
      str = str:gsub("\n", "\r\n")
      str = str:gsub("([^%w %-%_%.%~])", function(c)
        return string.format ("%%%02X", string.byte(c))
      end)
      str = str:gsub(" ", "%%20")
    end
    return str
  end

  local function cookie_encode(str, name)
    str = str:gsub("[,;%s]", "")

    if (name) then
      str = str:gsub("=", "")
    end

    return str
  end

  local auth_map = {
    BASIC = ffi.cast("long", curl.CURLAUTH_BASIC),
    DIGEST = ffi.cast("long", curl.CURLAUTH_DIGEST),
    NEGOTIATE = ffi.cast("long", curl.CURLAUTH_NEGOTIATE)
  }

  request = {
    error = {
      unknown = 0,
      timeout = 1
    },

    version = "2.2.0",
    version_major = 2,
    version_minor = 2,
    version_patch = 0,

    --[[
      Send an HTTP(S) request to the URL at 'url' using the HTTP method 'method'.
      Use the 'args' parameter to optionally configure the request:
        - method: HTTP method to use. Defaults to "GET", but can be any HTTP verb like "POST" or "PUT"
        - headers: Dictionary of additional HTTP headers to send with request
        - data: Dictionary or string to send as request body
        - cookies: Dictionary table of cookies to send
        - timeout: How long to wait for the connection to be made before giving up
        - allow_redirects: Whether or not to allow redirection. Defaults to true
        - body_stream_callback: A method to call with each piece of the response body.
        - header_stream_callback: A method to call with each piece of the resulting header.
        - transfer_info_callback: A method to call with transfer progress data.
        - auth_type: Authentication method to use. Defaults to "none", but can also be "basic", "digest" or "negotiate"
        - username: A username to use with authentication. 'auth_type' must also be specified.
        - password: A password to use with authentication. 'auth_type' must also be specified.
  
      If both body_stream_callback and header_stream_callback are defined, a boolean true will be returned instead of the following object.
  
      The return object is a dictionary with the following members:
        - code: The HTTP status code the response gave. Will not exist if header_stream_callback is defined above.
        - body: The body of the response. Will not exist if body_stream_callback is defined above.
        - headers: A dictionary of headers and their values. Will not exist if header_stream_callback is defined above.
        - headers_raw: A raw string containing the actual headers the server sent back. Will not exist if header_stream_callback is defined above.
        - set_cookies: A dictionary of cookies given by the "Set-Cookie" header from the server. Will not exist if the server did not set any cookies.
  
    ]]
    send = function(url, args)
      local handle = curl.curl_easy_init()
      local header_chunk
      local out_buffer
      local headers_buffer
      args = args or {}

      curl.curl_easy_setopt(handle, curl.CURLOPT_URL, url)
      curl.curl_easy_setopt(handle, curl.CURLOPT_SSL_VERIFYPEER, 1)
      curl.curl_easy_setopt(handle, curl.CURLOPT_SSL_VERIFYHOST, 2)

      if (args.method) then
        local method = string.upper(tostring(args.method))

        if (method == "GET") then
          curl.curl_easy_setopt(handle, curl.CURLOPT_HTTPGET, 1)
        elseif (method == "POST") then
          curl.curl_easy_setopt(handle, curl.CURLOPT_POST, 1)
        else
          curl.curl_easy_setopt(handle, curl.CURLOPT_CUSTOMREQUEST, method)
        end
      end

      if (args.headers) then
        for key, value in pairs(args.headers) do
          header_chunk = curl.curl_slist_append(header_chunk, tostring(key) .. ":" .. tostring(value))
        end

        curl.curl_easy_setopt(handle, curl.CURLOPT_HTTPHEADER, header_chunk)
      end

      if (args.auth_type) then
        local auth = string.upper(tostring(args.auth_type))

        if (auth_map[auth]) then
          curl.curl_easy_setopt(handle, curl.CURLOPT_HTTPAUTH, auth_map[auth])
          curl.curl_easy_setopt(handle, curl.CURLOPT_USERNAME, tostring(args.username))
          curl.curl_easy_setopt(handle, curl.CURLOPT_PASSWORD, tostring(args.password or ""))
        elseif (auth ~= "NONE") then
          error("Unsupported authentication type '" .. auth .. "'")
        end
      end

      if (args.body_stream_callback) then
        curl.curl_easy_setopt(handle, curl.CURLOPT_WRITEFUNCTION, ffi.cast("curl_callback", function(data, size, nmeb, user)
          args.body_stream_callback(ffi.string(data, size * nmeb))
          return size * nmeb
        end))
      else
        out_buffer = {}

        curl.curl_easy_setopt(handle, curl.CURLOPT_WRITEFUNCTION, ffi.cast("curl_callback", function(data, size, nmeb, user)
          table.insert(out_buffer, ffi.string(data, size * nmeb))
          return size * nmeb
        end))
      end

      if (args.header_stream_callback) then
        curl.curl_easy_setopt(handle, curl.CURLOPT_HEADERFUNCTION, ffi.cast("curl_callback", function(data, size, nmeb, user)
          args.header_stream_callback(ffi.string(data, size * nmeb))
          return size * nmeb
        end))
      else
        headers_buffer = {}

        curl.curl_easy_setopt(handle, curl.CURLOPT_HEADERFUNCTION, ffi.cast("curl_callback", function(data, size, nmeb, user)
          table.insert(headers_buffer, ffi.string(data, size * nmeb))
          return size * nmeb
        end))
      end

      if (args.transfer_info_callback) then
        curl.curl_easy_setopt(handle, curl.CURLOPT_NOPROGRESS, 0)
        curl.curl_easy_setopt(handle, curl.CURLOPT_XFERINFOFUNCTION, ffi.cast("curl_xferinfo_callback", function(client, dltotal, dlnow, ultotal, ulnow)
          args.transfer_info_callback(tonumber(dltotal), tonumber(dlnow), tonumber(ultotal), tonumber(ulnow))
          return 0
        end))
      end

      if (args.follow_redirects == nil) then
        curl.curl_easy_setopt(handle, curl.CURLOPT_FOLLOWLOCATION, true)
      else
        curl.curl_easy_setopt(handle, curl.CURLOPT_FOLLOWLOCATION, not not args.follow_redirects)
      end

      if (args.data) then
        if (type(args.data) == "table") then
          local buffer = {}
          for key, value in pairs(args.data) do
            table.insert(buffer, ("%s=%s"):format(url_encode(key), url_encode(value)))
          end

          curl.curl_easy_setopt(handle, curl.CURLOPT_POSTFIELDS, table.concat(buffer, "&"))
        else
          curl.curl_easy_setopt(handle, curl.CURLOPT_POSTFIELDS, tostring(args.data))
        end
      end

      if (args.cookies) then
        local cookie_out

        if (type(args.cookies) == "table") then
          local buffer = {}
          for key, value in pairs(args.cookies) do
            table.insert(buffer, ("%s=%s"):format(cookie_encode(key, true), cookie_encode(value)))
          end

          cookie_out = table.concat(buffer, "; ")
        else
          cookie_out = tostring(args.cookies)
        end

        curl.curl_easy_setopt(handle, curl.CURLOPT_COOKIE, cookie_out)
      end

      if (tonumber(args.timeout)) then
        curl.curl_easy_setopt(handle, curl.CURLOPT_CONNECTTIMEOUT, tonumber(args.timeout))
      end

      local result = curl.curl_easy_perform(handle)
      curl.curl_easy_cleanup(handle)
      curl.curl_slist_free_all(header_chunk)

      if (result == curl.CURLE_OK) then
        if (out_buffer or headers_buffer) then
          local headers, status, parsed_headers, set_cookies

          if (headers_buffer) then
            headers = table.concat(headers_buffer)
            status = headers:match("%s+(%d+)%s+")

            parsed_headers = {}

            for key, value in headers:gmatch("\n([^:]+):%s*([^\r\n]*)") do
              parsed_headers[key] = value
            end

            if (parsed_headers["Set-Cookie"]) then
              set_cookies = {}

              -- Get unquoted cookie values
              for key, value in parsed_headers["Set-Cookie"]:gmatch("%s*([^=]+)=([^;]*)") do
                set_cookies[key] = value
              end

              -- Get quoted cookie values
              for key, value in parsed_headers["Set-Cookie"]:gmatch("%s*([^=]+)=(%b\"\")") do
                set_cookies[key] = value:sub(2, -2)
              end
            end
          end

          return {
            body = table.concat(out_buffer),
            headers = parsed_headers,
            set_cookies = set_cookies,
            code = status,
            raw_headers = headers
          }
        else
          return true
        end
      elseif (result == curl.CURLE_OPERATION_TIMEDOUT) then
        return false, request.error.timeout, "Connection timed out"
      else
        return false, request.error.unknown, "Unknown error"
      end
    end,

    init = function()
      curl.curl_global_init(curl.CURL_GLOBAL_ALL)
    end,

    close = function()
      curl.curl_global_cleanup()
    end
  }

  request.init()

  return request end)
package.preload['love-update.vendor.luajit-request.luajit-curl'] = (function (...)
  --[[
  LuaJIT-cURL
  Lucien Greathouse
  LuaJIT FFI cURL binding aimed at cURL version 7.38.0.
  
  Copyright (c) 2014 lucien Greathouse
  
  This software is provided 'as-is', without any express
  or implied warranty. In no event will the authors be held
  liable for any damages arising from the use of this software.
  
  Permission is granted to anyone to use this software for any purpose,
  including commercial applications, andto alter it and redistribute it
  freely, subject to the following restrictions:
  
  1. The origin of this software must not be misrepresented; you must not
  claim that you wrote the original software. If you use this software
  in a product, an acknowledgment in the product documentation would be
  appreciated but is not required.
  
  2. Altered source versions must be plainly marked as such, and must
  not be misrepresented as being the original software.
  
  3. This notice may not be removed or altered from any source distribution.
  ]]

  local ffi = require("ffi")
  local curl = ffi.load("libcurl")

  if (jit.os == "Windows") then
    --Windows!
    ffi.cdef([[
		//windows layering
		enum {
			INVALID_SOCKET = ~0,
			SOCKET_BAD = ~0
		};
	]])
  else
    --Not Windows!
    ffi.cdef([[
		typedef int socket_t;

		enum {
			SOCKET_BAD = -1
		};
	]])
  end

  ffi.cdef([[
	typedef int64_t time_t;
	typedef unsigned int size_t;

	typedef size_t (*curl_callback)(char *data, size_t size, size_t nmeb, void *userdata);
]])

  --curlver.h
  ffi.cdef([[
/***************************************************************************
 *                                  _   _ ____  _
 *  Project                     ___| | | |  _ \| |
 *                             / __| | | | |_) | |
 *                            | (__| |_| |  _ <| |___
 *                             \___|\___/|_| \_\_____|
 *
 * Copyright (C) 1998 - 2014, Daniel Stenberg, <daniel@haxx.se>, et al.
 *
 * This software is licensed as described in the file COPYING, which
 * you should have received as part of this distribution. The terms
 * are also available at http://curl.haxx.se/docs/copyright.html.
 *
 * You may opt to use, copy, modify, merge, publish, distribute and/or sell
 * copies of the Software, and permit persons to whom the Software is
 * furnished to do so, under the terms of the COPYING file.
 *
 * This software is distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY
 * KIND, either express or implied.
 *
 ***************************************************************************/

enum {
	LIBCURL_VERSION_MAJOR = 7,
	LIBCURL_VERSION_MINOR = 38,
	LIBCURL_VERSION_PATCH = 0,
	LIBCURL_VERSION_NUM = 0x072600
}
]])

  --cURL's type aliasing, built around curlbuild.h
  ffi.cdef([[
	typedef int64_t curl_off_t;
]])

  --Constants
  ffi.cdef([[
enum {
	CURL_GLOBAL_SSL = (1<<0),
	CURL_GLOBAL_WIN32 = (1<<1),
	CURL_GLOBAL_ALL = (CURL_GLOBAL_SSL|CURL_GLOBAL_WIN32),
	CURL_GLOBAL_NOTHING = 0,
	CURL_GLOBAL_DEFAULT = CURL_GLOBAL_ALL,
	CURL_GLOBAL_ACK_EINTR = (1<<2)
};

enum {
	CURLAUTH_NONE = 0,
	CURLAUTH_BASIC = 1,
	CURLAUTH_DIGEST = 1<<1,
	CURLAUTH_NEGOTIATE = 1<<2
};
]])

  ffi.cdef([[
typedef void CURL;
typedef int curl_socket_t;
struct curl_httppost {
struct curl_httppost *next;
char *name;
long namelength;
char *contents;
long contentslength;
char *buffer;
long bufferlength;
char *contenttype;
struct curl_slist* contentheader;
struct curl_httppost *more;
long flags;
char *showfilename;
void *userp;
};
typedef int (*curl_progress_callback)(void *clientp,
double dltotal,
double dlnow,
double ultotal,
double ulnow);
typedef int (*curl_xferinfo_callback)(void *clientp,
curl_off_t dltotal,
curl_off_t dlnow,
curl_off_t ultotal,
curl_off_t ulnow);
typedef size_t (*curl_write_callback)(char *buffer,
size_t size,
size_t nitems,
void *outstream);
typedef enum {
CURLFILETYPE_FILE = 0,
CURLFILETYPE_DIRECTORY,
CURLFILETYPE_SYMLINK,
CURLFILETYPE_DEVICE_BLOCK,
CURLFILETYPE_DEVICE_CHAR,
CURLFILETYPE_NAMEDPIPE,
CURLFILETYPE_SOCKET,
CURLFILETYPE_DOOR,
CURLFILETYPE_UNKNOWN
} curlfiletype;
struct curl_fileinfo {
char *filename;
curlfiletype filetype;
time_t time;
unsigned int perm;
int uid;
int gid;
curl_off_t size;
long int hardlinks;
struct {
char *time;
char *perm;
char *user;
char *group;
char *target;
} strings;
unsigned int flags;
char * b_data;
size_t b_size;
size_t b_used;
};
typedef long (*curl_chunk_bgn_callback)(const void *transfer_info,
void *ptr,
int remains);
typedef long (*curl_chunk_end_callback)(void *ptr);
typedef int (*curl_fnmatch_callback)(void *ptr,
const char *pattern,
const char *string);
typedef int (*curl_seek_callback)(void *instream,
curl_off_t offset,
int origin);
typedef size_t (*curl_read_callback)(char *buffer,
size_t size,
size_t nitems,
void *instream);
typedef enum  {
CURLSOCKTYPE_IPCXN,
CURLSOCKTYPE_ACCEPT,
CURLSOCKTYPE_LAST
} curlsocktype;
typedef int (*curl_sockopt_callback)(void *clientp,
curl_socket_t curlfd,
curlsocktype purpose);
struct sockaddr {
uint8_t sa_family;
char sa_data[14];
};
struct curl_sockaddr {
int family;
int socktype;
int protocol;
unsigned int addrlen;
struct sockaddr addr;
};
typedef curl_socket_t
(*curl_opensocket_callback)(void *clientp,
curlsocktype purpose,
struct curl_sockaddr *address);
typedef int
(*curl_closesocket_callback)(void *clientp, curl_socket_t item);
typedef enum {
CURLIOE_OK,
CURLIOE_UNKNOWNCMD,
CURLIOE_FAILRESTART,
CURLIOE_LAST
} curlioerr;
typedef enum  {
CURLIOCMD_NOP,
CURLIOCMD_RESTARTREAD,
CURLIOCMD_LAST
} curliocmd;
typedef curlioerr (*curl_ioctl_callback)(CURL *handle,
int cmd,
void *clientp);
typedef void *(*curl_malloc_callback)(size_t size);
typedef void (*curl_free_callback)(void *ptr);
typedef void *(*curl_realloc_callback)(void *ptr, size_t size);
typedef char *(*curl_strdup_callback)(const char *str);
typedef void *(*curl_calloc_callback)(size_t nmemb, size_t size);
typedef enum {
CURLINFO_TEXT = 0,
CURLINFO_HEADER_IN,
CURLINFO_HEADER_OUT,
CURLINFO_DATA_IN,
CURLINFO_DATA_OUT,
CURLINFO_SSL_DATA_IN,
CURLINFO_SSL_DATA_OUT,
CURLINFO_END
} curl_infotype;
typedef int (*curl_debug_callback)
(CURL *handle,
curl_infotype type,
char *data,
size_t size,
void *userptr);
typedef enum {
CURLE_OK = 0,
CURLE_UNSUPPORTED_PROTOCOL,
CURLE_FAILED_INIT,
CURLE_URL_MALFORMAT,
CURLE_NOT_BUILT_IN,
CURLE_COULDNT_RESOLVE_PROXY,
CURLE_COULDNT_RESOLVE_HOST,
CURLE_COULDNT_CONNECT,
CURLE_FTP_WEIRD_SERVER_REPLY,
CURLE_REMOTE_ACCESS_DENIED,
CURLE_FTP_ACCEPT_FAILED,
CURLE_FTP_WEIRD_PASS_REPLY,
CURLE_FTP_ACCEPT_TIMEOUT,
CURLE_FTP_WEIRD_PASV_REPLY,
CURLE_FTP_WEIRD_227_FORMAT,
CURLE_FTP_CANT_GET_HOST,
CURLE_HTTP2,
CURLE_FTP_COULDNT_SET_TYPE,
CURLE_PARTIAL_FILE,
CURLE_FTP_COULDNT_RETR_FILE,
CURLE_OBSOLETE20,
CURLE_QUOTE_ERROR,
CURLE_HTTP_RETURNED_ERROR,
CURLE_WRITE_ERROR,
CURLE_OBSOLETE24,
CURLE_UPLOAD_FAILED,
CURLE_READ_ERROR,
CURLE_OUT_OF_MEMORY,
CURLE_OPERATION_TIMEDOUT,
CURLE_OBSOLETE29,
CURLE_FTP_PORT_FAILED,
CURLE_FTP_COULDNT_USE_REST,
CURLE_OBSOLETE32,
CURLE_RANGE_ERROR,
CURLE_HTTP_POST_ERROR,
CURLE_SSL_CONNECT_ERROR,
CURLE_BAD_DOWNLOAD_RESUME,
CURLE_FILE_COULDNT_READ_FILE,
CURLE_LDAP_CANNOT_BIND,
CURLE_LDAP_SEARCH_FAILED,
CURLE_OBSOLETE40,
CURLE_FUNCTION_NOT_FOUND,
CURLE_ABORTED_BY_CALLBACK,
CURLE_BAD_FUNCTION_ARGUMENT,
CURLE_OBSOLETE44,
CURLE_INTERFACE_FAILED,
CURLE_OBSOLETE46,
CURLE_TOO_MANY_REDIRECTS ,
CURLE_UNKNOWN_OPTION,
CURLE_TELNET_OPTION_SYNTAX ,
CURLE_OBSOLETE50,
CURLE_PEER_FAILED_VERIFICATION,
CURLE_GOT_NOTHING,
CURLE_SSL_ENGINE_NOTFOUND,
CURLE_SSL_ENGINE_SETFAILED,
CURLE_SEND_ERROR,
CURLE_RECV_ERROR,
CURLE_OBSOLETE57,
CURLE_SSL_CERTPROBLEM,
CURLE_SSL_CIPHER,
CURLE_SSL_CACERT,
CURLE_BAD_CONTENT_ENCODING,
CURLE_LDAP_INVALID_URL,
CURLE_FILESIZE_EXCEEDED,
CURLE_USE_SSL_FAILED,
CURLE_SEND_FAIL_REWIND,
CURLE_SSL_ENGINE_INITFAILED,
CURLE_LOGIN_DENIED,
CURLE_TFTP_NOTFOUND,
CURLE_TFTP_PERM,
CURLE_REMOTE_DISK_FULL,
CURLE_TFTP_ILLEGAL,
CURLE_TFTP_UNKNOWNID,
CURLE_REMOTE_FILE_EXISTS,
CURLE_TFTP_NOSUCHUSER,
CURLE_CONV_FAILED,
CURLE_CONV_REQD,
CURLE_SSL_CACERT_BADFILE,
CURLE_REMOTE_FILE_NOT_FOUND,
CURLE_SSH,
CURLE_SSL_SHUTDOWN_FAILED,
CURLE_AGAIN,
CURLE_SSL_CRL_BADFILE,
CURLE_SSL_ISSUER_ERROR,
CURLE_FTP_PRET_FAILED,
CURLE_RTSP_CSEQ_ERROR,
CURLE_RTSP_SESSION_ERROR,
CURLE_FTP_BAD_FILE_LIST,
CURLE_CHUNK_FAILED,
CURLE_NO_CONNECTION_AVAILABLE,
CURL_LAST
} CURLcode;
typedef CURLcode (*curl_conv_callback)(char *buffer, size_t length);
typedef CURLcode (*curl_ssl_ctx_callback)(CURL *curl,
void *ssl_ctx,
void *userptr);
typedef enum {
CURLPROXY_HTTP = 0,
CURLPROXY_HTTP_1_0 = 1,
CURLPROXY_SOCKS4 = 4,
CURLPROXY_SOCKS5 = 5,
CURLPROXY_SOCKS4A = 6,
CURLPROXY_SOCKS5_HOSTNAME = 7
} curl_proxytype;
enum curl_khtype {
CURLKHTYPE_UNKNOWN,
CURLKHTYPE_RSA1,
CURLKHTYPE_RSA,
CURLKHTYPE_DSS
};
struct curl_khkey {
const char *key;
size_t len;
enum curl_khtype keytype;
};
enum curl_khstat {
CURLKHSTAT_FINE_ADD_TO_FILE,
CURLKHSTAT_FINE,
CURLKHSTAT_REJECT,
CURLKHSTAT_DEFER,
CURLKHSTAT_LAST
};
enum curl_khmatch {
CURLKHMATCH_OK,
CURLKHMATCH_MISMATCH,
CURLKHMATCH_MISSING,
CURLKHMATCH_LAST
};
typedef int
(*curl_sshkeycallback) (CURL *easy,
const struct curl_khkey *knownkey,
const struct curl_khkey *foundkey,
enum curl_khmatch,
void *clientp);
typedef enum {
CURLUSESSL_NONE,
CURLUSESSL_TRY,
CURLUSESSL_CONTROL,
CURLUSESSL_ALL,
CURLUSESSL_LAST
} curl_usessl;
typedef enum {
CURLFTPSSL_CCC_NONE,
CURLFTPSSL_CCC_PASSIVE,
CURLFTPSSL_CCC_ACTIVE,
CURLFTPSSL_CCC_LAST
} curl_ftpccc;
typedef enum {
CURLFTPAUTH_DEFAULT,
CURLFTPAUTH_SSL,
CURLFTPAUTH_TLS,
CURLFTPAUTH_LAST
} curl_ftpauth;
typedef enum {
CURLFTP_CREATE_DIR_NONE,
CURLFTP_CREATE_DIR,
CURLFTP_CREATE_DIR_RETRY,
CURLFTP_CREATE_DIR_LAST
} curl_ftpcreatedir;
typedef enum {
CURLFTPMETHOD_DEFAULT,
CURLFTPMETHOD_MULTICWD,
CURLFTPMETHOD_NOCWD,
CURLFTPMETHOD_SINGLECWD,
CURLFTPMETHOD_LAST
} curl_ftpmethod;
typedef enum {
CURLOPT_WRITEDATA = 10000 + 1,
CURLOPT_URL = 10000 + 2,
CURLOPT_PORT = 0 + 3,
CURLOPT_PROXY = 10000 + 4,
CURLOPT_USERPWD = 10000 + 5,
CURLOPT_PROXYUSERPWD = 10000 + 6,
CURLOPT_RANGE = 10000 + 7,
CURLOPT_READDATA = 10000 + 9,
CURLOPT_ERRORBUFFER = 10000 + 10,
CURLOPT_WRITEFUNCTION = 20000 + 11,
CURLOPT_READFUNCTION = 20000 + 12,
CURLOPT_TIMEOUT = 0 + 13,
CURLOPT_INFILESIZE = 0 + 14,
CURLOPT_POSTFIELDS = 10000 + 15,
CURLOPT_REFERER = 10000 + 16,
CURLOPT_FTPPORT = 10000 + 17,
CURLOPT_USERAGENT = 10000 + 18,
CURLOPT_LOW_SPEED_LIMIT = 0 + 19,
CURLOPT_LOW_SPEED_TIME = 0 + 20,
CURLOPT_RESUME_FROM = 0 + 21,
CURLOPT_COOKIE = 10000 + 22,
CURLOPT_HTTPHEADER = 10000 + 23,
CURLOPT_HTTPPOST = 10000 + 24,
CURLOPT_SSLCERT = 10000 + 25,
CURLOPT_KEYPASSWD = 10000 + 26,
CURLOPT_CRLF = 0 + 27,
CURLOPT_QUOTE = 10000 + 28,
CURLOPT_HEADERDATA = 10000 + 29,
CURLOPT_COOKIEFILE = 10000 + 31,
CURLOPT_SSLVERSION = 0 + 32,
CURLOPT_TIMECONDITION = 0 + 33,
CURLOPT_TIMEVALUE = 0 + 34,
CURLOPT_CUSTOMREQUEST = 10000 + 36,
CURLOPT_STDERR = 10000 + 37,
CURLOPT_POSTQUOTE = 10000 + 39,
CURLOPT_OBSOLETE40 = 10000 + 40,
CURLOPT_VERBOSE = 0 + 41,
CURLOPT_HEADER = 0 + 42,
CURLOPT_NOPROGRESS = 0 + 43,
CURLOPT_NOBODY = 0 + 44,
CURLOPT_FAILONERROR = 0 + 45,
CURLOPT_UPLOAD = 0 + 46,
CURLOPT_POST = 0 + 47,
CURLOPT_DIRLISTONLY = 0 + 48,
CURLOPT_APPEND = 0 + 50,
CURLOPT_NETRC = 0 + 51,
CURLOPT_FOLLOWLOCATION = 0 + 52,
CURLOPT_TRANSFERTEXT = 0 + 53,
CURLOPT_PUT = 0 + 54,
CURLOPT_PROGRESSFUNCTION = 20000 + 56,
CURLOPT_PROGRESSDATA = 10000 + 57,
CURLOPT_AUTOREFERER = 0 + 58,
CURLOPT_PROXYPORT = 0 + 59,
CURLOPT_POSTFIELDSIZE = 0 + 60,
CURLOPT_HTTPPROXYTUNNEL = 0 + 61,
CURLOPT_INTERFACE = 10000 + 62,
CURLOPT_KRBLEVEL = 10000 + 63,
CURLOPT_SSL_VERIFYPEER = 0 + 64,
CURLOPT_CAINFO = 10000 + 65,
CURLOPT_MAXREDIRS = 0 + 68,
CURLOPT_FILETIME = 0 + 69,
CURLOPT_TELNETOPTIONS = 10000 + 70,
CURLOPT_MAXCONNECTS = 0 + 71,
CURLOPT_OBSOLETE72 = 0 + 72,
CURLOPT_FRESH_CONNECT = 0 + 74,
CURLOPT_FORBID_REUSE = 0 + 75,
CURLOPT_RANDOM_FILE = 10000 + 76,
CURLOPT_EGDSOCKET = 10000 + 77,
CURLOPT_CONNECTTIMEOUT = 0 + 78,
CURLOPT_HEADERFUNCTION = 20000 + 79,
CURLOPT_HTTPGET = 0 + 80,
CURLOPT_SSL_VERIFYHOST = 0 + 81,
CURLOPT_COOKIEJAR = 10000 + 82,
CURLOPT_SSL_CIPHER_LIST = 10000 + 83,
CURLOPT_HTTP_VERSION = 0 + 84,
CURLOPT_FTP_USE_EPSV = 0 + 85,
CURLOPT_SSLCERTTYPE = 10000 + 86,
CURLOPT_SSLKEY = 10000 + 87,
CURLOPT_SSLKEYTYPE = 10000 + 88,
CURLOPT_SSLENGINE = 10000 + 89,
CURLOPT_SSLENGINE_DEFAULT = 0 + 90,
CURLOPT_DNS_USE_GLOBAL_CACHE = 0 + 91,
CURLOPT_DNS_CACHE_TIMEOUT = 0 + 92,
CURLOPT_PREQUOTE = 10000 + 93,
CURLOPT_DEBUGFUNCTION = 20000 + 94,
CURLOPT_DEBUGDATA = 10000 + 95,
CURLOPT_COOKIESESSION = 0 + 96,
CURLOPT_CAPATH = 10000 + 97,
CURLOPT_BUFFERSIZE = 0 + 98,
CURLOPT_NOSIGNAL = 0 + 99,
CURLOPT_SHARE = 10000 + 100,
CURLOPT_PROXYTYPE = 0 + 101,
CURLOPT_ACCEPT_ENCODING = 10000 + 102,
CURLOPT_PRIVATE = 10000 + 103,
CURLOPT_HTTP200ALIASES = 10000 + 104,
CURLOPT_UNRESTRICTED_AUTH = 0 + 105,
CURLOPT_FTP_USE_EPRT = 0 + 106,
CURLOPT_HTTPAUTH = 0 + 107,
CURLOPT_SSL_CTX_FUNCTION = 20000 + 108,
CURLOPT_SSL_CTX_DATA = 10000 + 109,
CURLOPT_FTP_CREATE_MISSING_DIRS = 0 + 110,
CURLOPT_PROXYAUTH = 0 + 111,
CURLOPT_FTP_RESPONSE_TIMEOUT = 0 + 112,
CURLOPT_IPRESOLVE = 0 + 113,
CURLOPT_MAXFILESIZE = 0 + 114,
CURLOPT_INFILESIZE_LARGE = 30000 + 115,
CURLOPT_RESUME_FROM_LARGE = 30000 + 116,
CURLOPT_MAXFILESIZE_LARGE = 30000 + 117,
CURLOPT_NETRC_FILE = 10000 + 118,
CURLOPT_USE_SSL = 0 + 119,
CURLOPT_POSTFIELDSIZE_LARGE = 30000 + 120,
CURLOPT_TCP_NODELAY = 0 + 121,
CURLOPT_FTPSSLAUTH = 0 + 129,
CURLOPT_IOCTLFUNCTION = 20000 + 130,
CURLOPT_IOCTLDATA = 10000 + 131,
CURLOPT_FTP_ACCOUNT = 10000 + 134,
CURLOPT_COOKIELIST = 10000 + 135,
CURLOPT_IGNORE_CONTENT_LENGTH = 0 + 136,
CURLOPT_FTP_SKIP_PASV_IP = 0 + 137,
CURLOPT_FTP_FILEMETHOD = 0 + 138,
CURLOPT_LOCALPORT = 0 + 139,
CURLOPT_LOCALPORTRANGE = 0 + 140,
CURLOPT_CONNECT_ONLY = 0 + 141,
CURLOPT_CONV_FROM_NETWORK_FUNCTION = 20000 + 142,
CURLOPT_CONV_TO_NETWORK_FUNCTION = 20000 + 143,
CURLOPT_CONV_FROM_UTF8_FUNCTION = 20000 + 144,
CURLOPT_MAX_SEND_SPEED_LARGE = 30000 + 145,
CURLOPT_MAX_RECV_SPEED_LARGE = 30000 + 146,
CURLOPT_FTP_ALTERNATIVE_TO_USER = 10000 + 147,
CURLOPT_SOCKOPTFUNCTION = 20000 + 148,
CURLOPT_SOCKOPTDATA = 10000 + 149,
CURLOPT_SSL_SESSIONID_CACHE = 0 + 150,
CURLOPT_SSH_AUTH_TYPES = 0 + 151,
CURLOPT_SSH_PUBLIC_KEYFILE = 10000 + 152,
CURLOPT_SSH_PRIVATE_KEYFILE = 10000 + 153,
CURLOPT_FTP_SSL_CCC = 0 + 154,
CURLOPT_TIMEOUT_MS = 0 + 155,
CURLOPT_CONNECTTIMEOUT_MS = 0 + 156,
CURLOPT_HTTP_TRANSFER_DECODING = 0 + 157,
CURLOPT_HTTP_CONTENT_DECODING = 0 + 158,
CURLOPT_NEW_FILE_PERMS = 0 + 159,
CURLOPT_NEW_DIRECTORY_PERMS = 0 + 160,
CURLOPT_POSTREDIR = 0 + 161,
CURLOPT_SSH_HOST_PUBLIC_KEY_MD5 = 10000 + 162,
CURLOPT_OPENSOCKETFUNCTION = 20000 + 163,
CURLOPT_OPENSOCKETDATA = 10000 + 164,
CURLOPT_COPYPOSTFIELDS = 10000 + 165,
CURLOPT_PROXY_TRANSFER_MODE = 0 + 166,
CURLOPT_SEEKFUNCTION = 20000 + 167,
CURLOPT_SEEKDATA = 10000 + 168,
CURLOPT_CRLFILE = 10000 + 169,
CURLOPT_ISSUERCERT = 10000 + 170,
CURLOPT_ADDRESS_SCOPE = 0 + 171,
CURLOPT_CERTINFO = 0 + 172,
CURLOPT_USERNAME = 10000 + 173,
CURLOPT_PASSWORD = 10000 + 174,
CURLOPT_PROXYUSERNAME = 10000 + 175,
CURLOPT_PROXYPASSWORD = 10000 + 176,
CURLOPT_NOPROXY = 10000 + 177,
CURLOPT_TFTP_BLKSIZE = 0 + 178,
CURLOPT_SOCKS5_GSSAPI_SERVICE = 10000 + 179,
CURLOPT_SOCKS5_GSSAPI_NEC = 0 + 180,
CURLOPT_PROTOCOLS = 0 + 181,
CURLOPT_REDIR_PROTOCOLS = 0 + 182,
CURLOPT_SSH_KNOWNHOSTS = 10000 + 183,
CURLOPT_SSH_KEYFUNCTION = 20000 + 184,
CURLOPT_SSH_KEYDATA = 10000 + 185,
CURLOPT_MAIL_FROM = 10000 + 186,
CURLOPT_MAIL_RCPT = 10000 + 187,
CURLOPT_FTP_USE_PRET = 0 + 188,
CURLOPT_RTSP_REQUEST = 0 + 189,
CURLOPT_RTSP_SESSION_ID = 10000 + 190,
CURLOPT_RTSP_STREAM_URI = 10000 + 191,
CURLOPT_RTSP_TRANSPORT = 10000 + 192,
CURLOPT_RTSP_CLIENT_CSEQ = 0 + 193,
CURLOPT_RTSP_SERVER_CSEQ = 0 + 194,
CURLOPT_INTERLEAVEDATA = 10000 + 195,
CURLOPT_INTERLEAVEFUNCTION = 20000 + 196,
CURLOPT_WILDCARDMATCH = 0 + 197,
CURLOPT_CHUNK_BGN_FUNCTION = 20000 + 198,
CURLOPT_CHUNK_END_FUNCTION = 20000 + 199,
CURLOPT_FNMATCH_FUNCTION = 20000 + 200,
CURLOPT_CHUNK_DATA = 10000 + 201,
CURLOPT_FNMATCH_DATA = 10000 + 202,
CURLOPT_RESOLVE = 10000 + 203,
CURLOPT_TLSAUTH_USERNAME = 10000 + 204,
CURLOPT_TLSAUTH_PASSWORD = 10000 + 205,
CURLOPT_TLSAUTH_TYPE = 10000 + 206,
CURLOPT_TRANSFER_ENCODING = 0 + 207,
CURLOPT_CLOSESOCKETFUNCTION = 20000 + 208,
CURLOPT_CLOSESOCKETDATA = 10000 + 209,
CURLOPT_GSSAPI_DELEGATION = 0 + 210,
CURLOPT_DNS_SERVERS = 10000 + 211,
CURLOPT_ACCEPTTIMEOUT_MS = 0 + 212,
CURLOPT_TCP_KEEPALIVE = 0 + 213,
CURLOPT_TCP_KEEPIDLE = 0 + 214,
CURLOPT_TCP_KEEPINTVL = 0 + 215,
CURLOPT_SSL_OPTIONS = 0 + 216,
CURLOPT_MAIL_AUTH = 10000 + 217,
CURLOPT_SASL_IR = 0 + 218,
CURLOPT_XFERINFOFUNCTION = 20000 + 219,
CURLOPT_XOAUTH2_BEARER = 10000 + 220,
CURLOPT_DNS_INTERFACE = 10000 + 221,
CURLOPT_DNS_LOCAL_IP4 = 10000 + 222,
CURLOPT_DNS_LOCAL_IP6 = 10000 + 223,
CURLOPT_LOGIN_OPTIONS = 10000 + 224,
CURLOPT_SSL_ENABLE_NPN = 0 + 225,
CURLOPT_SSL_ENABLE_ALPN = 0 + 226,
CURLOPT_EXPECT_100_TIMEOUT_MS = 0 + 227,
CURLOPT_PROXYHEADER = 10000 + 228,
CURLOPT_HEADEROPT = 0 + 229,
CURLOPT_LASTENTRY
} CURLoption;
enum {
CURL_HTTP_VERSION_NONE,
CURL_HTTP_VERSION_1_0,
CURL_HTTP_VERSION_1_1,
CURL_HTTP_VERSION_2_0,
CURL_HTTP_VERSION_LAST
};
enum {
CURL_RTSPREQ_NONE,
CURL_RTSPREQ_OPTIONS,
CURL_RTSPREQ_DESCRIBE,
CURL_RTSPREQ_ANNOUNCE,
CURL_RTSPREQ_SETUP,
CURL_RTSPREQ_PLAY,
CURL_RTSPREQ_PAUSE,
CURL_RTSPREQ_TEARDOWN,
CURL_RTSPREQ_GET_PARAMETER,
CURL_RTSPREQ_SET_PARAMETER,
CURL_RTSPREQ_RECORD,
CURL_RTSPREQ_RECEIVE,
CURL_RTSPREQ_LAST
};
enum CURL_NETRC_OPTION {
CURL_NETRC_IGNORED,
CURL_NETRC_OPTIONAL,
CURL_NETRC_REQUIRED,
CURL_NETRC_LAST
};
enum {
CURL_SSLVERSION_DEFAULT,
CURL_SSLVERSION_TLSv1,
CURL_SSLVERSION_SSLv2,
CURL_SSLVERSION_SSLv3,
CURL_SSLVERSION_TLSv1_0,
CURL_SSLVERSION_TLSv1_1,
CURL_SSLVERSION_TLSv1_2,
CURL_SSLVERSION_LAST
};
enum CURL_TLSAUTH {
CURL_TLSAUTH_NONE,
CURL_TLSAUTH_SRP,
CURL_TLSAUTH_LAST
};
typedef enum {
CURL_TIMECOND_NONE,
CURL_TIMECOND_IFMODSINCE,
CURL_TIMECOND_IFUNMODSINCE,
CURL_TIMECOND_LASTMOD,
CURL_TIMECOND_LAST
} curl_TimeCond;
 int (curl_strequal)(const char *s1, const char *s2);
 int (curl_strnequal)(const char *s1, const char *s2, size_t n);
typedef enum {
CURLFORM_NOTHING,
CURLFORM_COPYNAME,
CURLFORM_PTRNAME,
CURLFORM_NAMELENGTH,
CURLFORM_COPYCONTENTS,
CURLFORM_PTRCONTENTS,
CURLFORM_CONTENTSLENGTH,
CURLFORM_FILECONTENT,
CURLFORM_ARRAY,
CURLFORM_OBSOLETE,
CURLFORM_FILE,
CURLFORM_BUFFER,
CURLFORM_BUFFERPTR,
CURLFORM_BUFFERLENGTH,
CURLFORM_CONTENTTYPE,
CURLFORM_CONTENTHEADER,
CURLFORM_FILENAME,
CURLFORM_END,
CURLFORM_OBSOLETE2,
CURLFORM_STREAM,
CURLFORM_LASTENTRY
} CURLformoption;
struct curl_forms {
CURLformoption option;
const char     *value;
};
typedef enum {
CURL_FORMADD_OK,
CURL_FORMADD_MEMORY,
CURL_FORMADD_OPTION_TWICE,
CURL_FORMADD_NULL,
CURL_FORMADD_UNKNOWN_OPTION,
CURL_FORMADD_INCOMPLETE,
CURL_FORMADD_ILLEGAL_ARRAY,
CURL_FORMADD_DISABLED,
CURL_FORMADD_LAST
} CURLFORMcode;
 CURLFORMcode curl_formadd(struct curl_httppost **httppost,
struct curl_httppost **last_post,
...);
typedef size_t (*curl_formget_callback)(void *arg, const char *buf,
size_t len);
 int curl_formget(struct curl_httppost *form, void *arg,
curl_formget_callback append);
 void curl_formfree(struct curl_httppost *form);
 char *curl_getenv(const char *variable);
 char *curl_version(void);
 char *curl_easy_escape(CURL *handle,
const char *string,
int length);
 char *curl_escape(const char *string,
int length);
 char *curl_easy_unescape(CURL *handle,
const char *string,
int length,
int *outlength);
 char *curl_unescape(const char *string,
int length);
 void curl_free(void *p);
 CURLcode curl_global_init(long flags);
 CURLcode curl_global_init_mem(long flags,
curl_malloc_callback m,
curl_free_callback f,
curl_realloc_callback r,
curl_strdup_callback s,
curl_calloc_callback c);
 void curl_global_cleanup(void);
struct curl_slist {
char *data;
struct curl_slist *next;
};
 struct curl_slist *curl_slist_append(struct curl_slist *,
const char *);
 void curl_slist_free_all(struct curl_slist *);
 time_t curl_getdate(const char *p, const time_t *unused);
struct curl_certinfo {
int num_of_certs;
struct curl_slist **certinfo;
};
typedef enum {
CURLSSLBACKEND_NONE = 0,
CURLSSLBACKEND_OPENSSL = 1,
CURLSSLBACKEND_GNUTLS = 2,
CURLSSLBACKEND_NSS = 3,
CURLSSLBACKEND_QSOSSL = 4,
CURLSSLBACKEND_GSKIT = 5,
CURLSSLBACKEND_POLARSSL = 6,
CURLSSLBACKEND_CYASSL = 7,
CURLSSLBACKEND_SCHANNEL = 8,
CURLSSLBACKEND_DARWINSSL = 9,
CURLSSLBACKEND_AXTLS = 10
} curl_sslbackend;
struct curl_tlssessioninfo {
curl_sslbackend backend;
void *internals;
};
typedef enum {
CURLINFO_NONE,
CURLINFO_EFFECTIVE_URL    =1048576 + 1,
CURLINFO_RESPONSE_CODE    =2097152   + 2,
CURLINFO_TOTAL_TIME       =3145728 + 3,
CURLINFO_NAMELOOKUP_TIME  =3145728 + 4,
CURLINFO_CONNECT_TIME     =3145728 + 5,
CURLINFO_PRETRANSFER_TIME =3145728 + 6,
CURLINFO_SIZE_UPLOAD      =3145728 + 7,
CURLINFO_SIZE_DOWNLOAD    =3145728 + 8,
CURLINFO_SPEED_DOWNLOAD   =3145728 + 9,
CURLINFO_SPEED_UPLOAD     =3145728 + 10,
CURLINFO_HEADER_SIZE      =2097152   + 11,
CURLINFO_REQUEST_SIZE     =2097152   + 12,
CURLINFO_SSL_VERIFYRESULT =2097152   + 13,
CURLINFO_FILETIME         =2097152   + 14,
CURLINFO_CONTENT_LENGTH_DOWNLOAD   =3145728 + 15,
CURLINFO_CONTENT_LENGTH_UPLOAD     =3145728 + 16,
CURLINFO_STARTTRANSFER_TIME =3145728 + 17,
CURLINFO_CONTENT_TYPE     =1048576 + 18,
CURLINFO_REDIRECT_TIME    =3145728 + 19,
CURLINFO_REDIRECT_COUNT   =2097152   + 20,
CURLINFO_PRIVATE          =1048576 + 21,
CURLINFO_HTTP_CONNECTCODE =2097152   + 22,
CURLINFO_HTTPAUTH_AVAIL   =2097152   + 23,
CURLINFO_PROXYAUTH_AVAIL  =2097152   + 24,
CURLINFO_OS_ERRNO         =2097152   + 25,
CURLINFO_NUM_CONNECTS     =2097152   + 26,
CURLINFO_SSL_ENGINES      =4194304  + 27,
CURLINFO_COOKIELIST       =4194304  + 28,
CURLINFO_LASTSOCKET       =2097152   + 29,
CURLINFO_FTP_ENTRY_PATH   =1048576 + 30,
CURLINFO_REDIRECT_URL     =1048576 + 31,
CURLINFO_PRIMARY_IP       =1048576 + 32,
CURLINFO_APPCONNECT_TIME  =3145728 + 33,
CURLINFO_CERTINFO         =4194304  + 34,
CURLINFO_CONDITION_UNMET  =2097152   + 35,
CURLINFO_RTSP_SESSION_ID  =1048576 + 36,
CURLINFO_RTSP_CLIENT_CSEQ =2097152   + 37,
CURLINFO_RTSP_SERVER_CSEQ =2097152   + 38,
CURLINFO_RTSP_CSEQ_RECV   =2097152   + 39,
CURLINFO_PRIMARY_PORT     =2097152   + 40,
CURLINFO_LOCAL_IP         =1048576 + 41,
CURLINFO_LOCAL_PORT       =2097152   + 42,
CURLINFO_TLS_SESSION      =4194304  + 43,
CURLINFO_LASTONE          = 43
} CURLINFO;
typedef enum {
CURLCLOSEPOLICY_NONE,
CURLCLOSEPOLICY_OLDEST,
CURLCLOSEPOLICY_LEAST_RECENTLY_USED,
CURLCLOSEPOLICY_LEAST_TRAFFIC,
CURLCLOSEPOLICY_SLOWEST,
CURLCLOSEPOLICY_CALLBACK,
CURLCLOSEPOLICY_LAST
} curl_closepolicy;
typedef enum {
CURL_LOCK_DATA_NONE = 0,
CURL_LOCK_DATA_SHARE,
CURL_LOCK_DATA_COOKIE,
CURL_LOCK_DATA_DNS,
CURL_LOCK_DATA_SSL_SESSION,
CURL_LOCK_DATA_CONNECT,
CURL_LOCK_DATA_LAST
} curl_lock_data;
typedef enum {
CURL_LOCK_ACCESS_NONE = 0,
CURL_LOCK_ACCESS_SHARED = 1,
CURL_LOCK_ACCESS_SINGLE = 2,
CURL_LOCK_ACCESS_LAST
} curl_lock_access;
typedef void (*curl_lock_function)(CURL *handle,
curl_lock_data data,
curl_lock_access locktype,
void *userptr);
typedef void (*curl_unlock_function)(CURL *handle,
curl_lock_data data,
void *userptr);
typedef void CURLSH;
typedef enum {
CURLSHE_OK,
CURLSHE_BAD_OPTION,
CURLSHE_IN_USE,
CURLSHE_INVALID,
CURLSHE_NOMEM,
CURLSHE_NOT_BUILT_IN,
CURLSHE_LAST
} CURLSHcode;
typedef enum {
CURLSHOPT_NONE,
CURLSHOPT_SHARE,
CURLSHOPT_UNSHARE,
CURLSHOPT_LOCKFUNC,
CURLSHOPT_UNLOCKFUNC,
CURLSHOPT_USERDATA,
CURLSHOPT_LAST
} CURLSHoption;
 CURLSH *curl_share_init(void);
 CURLSHcode curl_share_setopt(CURLSH *, CURLSHoption option, ...);
 CURLSHcode curl_share_cleanup(CURLSH *);
typedef enum {
CURLVERSION_FIRST,
CURLVERSION_SECOND,
CURLVERSION_THIRD,
CURLVERSION_FOURTH,
CURLVERSION_LAST
} CURLversion;
typedef struct {
CURLversion age;
const char *version;
unsigned int version_num;
const char *host;
int features;
const char *ssl_version;
long ssl_version_num;
const char *libz_version;
const char * const *protocols;
const char *ares;
int ares_num;
const char *libidn;
int iconv_ver_num;
const char *libssh_version;
} curl_version_info_data;
 curl_version_info_data *curl_version_info(CURLversion);
 const char *curl_easy_strerror(CURLcode);
 const char *curl_share_strerror(CURLSHcode);
 CURLcode curl_easy_pause(CURL *handle, int bitmask);
 CURL *curl_easy_init(void);
 CURLcode curl_easy_setopt(CURL *curl, CURLoption option, ...);
 CURLcode curl_easy_perform(CURL *curl);
 void curl_easy_cleanup(CURL *curl);
 CURLcode curl_easy_getinfo(CURL *curl, CURLINFO info, ...);
 CURL* curl_easy_duphandle(CURL *curl);
 void curl_easy_reset(CURL *curl);
 CURLcode curl_easy_recv(CURL *curl, void *buffer, size_t buflen,
size_t *n);
 CURLcode curl_easy_send(CURL *curl, const void *buffer,
size_t buflen, size_t *n);
typedef void CURLM;
typedef enum {
CURLM_CALL_MULTI_PERFORM = -1,
CURLM_OK,
CURLM_BAD_HANDLE,
CURLM_BAD_EASY_HANDLE,
CURLM_OUT_OF_MEMORY,
CURLM_INTERNAL_ERROR,
CURLM_BAD_SOCKET,
CURLM_UNKNOWN_OPTION,
CURLM_ADDED_ALREADY,
CURLM_LAST
} CURLMcode;
typedef enum {
CURLMSG_NONE,
CURLMSG_DONE,
CURLMSG_LAST
} CURLMSG;
struct CURLMsg {
CURLMSG msg;
CURL *easy_handle;
union {
void *whatever;
CURLcode result;
} data;
};
typedef struct CURLMsg CURLMsg;
struct curl_waitfd {
curl_socket_t fd;
short events;
short revents;
};
typedef struct fd_set {
        unsigned int   fd_count;               /* how many are SET? */
        curl_socket_t  fd_array[64]; //FD_SETSIZE, 64 on my machine, TOFIX
} fd_set;
 CURLM *curl_multi_init(void);
 CURLMcode curl_multi_add_handle(CURLM *multi_handle,
CURL *curl_handle);
 CURLMcode curl_multi_remove_handle(CURLM *multi_handle,
CURL *curl_handle);
 CURLMcode curl_multi_fdset(CURLM *multi_handle,
fd_set *read_fd_set,
fd_set *write_fd_set,
fd_set *exc_fd_set,
int *max_fd);
 CURLMcode curl_multi_wait(CURLM *multi_handle,
struct curl_waitfd extra_fds[],
unsigned int extra_nfds,
int timeout_ms,
int *ret);
 CURLMcode curl_multi_perform(CURLM *multi_handle,
int *running_handles);
 CURLMcode curl_multi_cleanup(CURLM *multi_handle);
 CURLMsg *curl_multi_info_read(CURLM *multi_handle,
int *msgs_in_queue);
 const char *curl_multi_strerror(CURLMcode);
typedef int (*curl_socket_callback)(CURL *easy,
curl_socket_t s,
int what,
void *userp,
void *socketp);
typedef int (*curl_multi_timer_callback)(CURLM *multi,
long timeout_ms,
void *userp);
 CURLMcode curl_multi_socket(CURLM *multi_handle, curl_socket_t s,
int *running_handles);
 CURLMcode curl_multi_socket_action(CURLM *multi_handle,
curl_socket_t s,
int ev_bitmask,
int *running_handles);
 CURLMcode curl_multi_socket_all(CURLM *multi_handle,
int *running_handles);
 CURLMcode curl_multi_timeout(CURLM *multi_handle,
long *milliseconds);
typedef enum {
CURLMOPT_SOCKETFUNCTION = 20000 + 1,
CURLMOPT_SOCKETDATA = 10000 + 2,
CURLMOPT_PIPELINING = 0 + 3,
CURLMOPT_TIMERFUNCTION = 20000 + 4,
CURLMOPT_TIMERDATA = 10000 + 5,
CURLMOPT_MAXCONNECTS = 0 + 6,
CURLMOPT_MAX_HOST_CONNECTIONS = 0 + 7,
CURLMOPT_MAX_PIPELINE_LENGTH = 0 + 8,
CURLMOPT_CONTENT_LENGTH_PENALTY_SIZE = 30000 + 9,
CURLMOPT_CHUNK_LENGTH_PENALTY_SIZE = 30000 + 10,
CURLMOPT_PIPELINING_SITE_BL = 10000 + 11,
CURLMOPT_PIPELINING_SERVER_BL = 10000 + 12,
CURLMOPT_MAX_TOTAL_CONNECTIONS = 0 + 13,
CURLMOPT_LASTENTRY
} CURLMoption;
 CURLMcode curl_multi_setopt(CURLM *multi_handle,
CURLMoption option, ...);
 CURLMcode curl_multi_assign(CURLM *multi_handle,
curl_socket_t sockfd, void *sockp);
]])

  return curl end)
package.preload['love-update.vendor.promise'] = (function (...)
  -- Port of https://github.com/rhysbrettbowen/promise_impl/blob/master/promise.js
  -- and https://github.com/rhysbrettbowen/Aplus
  --
  local queue = {}

  local State = {
    PENDING   = 'pending',
    FULFILLED = 'fulfilled',
    REJECTED  = 'rejected',
  }

  local passthrough = function(x) return x end
  local errorthrough = function(x) error(x) end

  local function callable_table(callback)
    local mt = getmetatable(callback)
    return type(mt) == 'table' and type(mt.__call) == 'function'
  end

  local function is_callable(value)
    local t = type(value)
    return t == 'function' or (t == 'table' and callable_table(value))
  end

  local transition, resolve, run

  local Promise = {
    is_promise = true,
    state = State.PENDING
  }
  Promise.mt = { __index = Promise }

  local do_async = function(callback)
    if Promise.async then
      Promise.async(callback)
    else
      table.insert(queue, callback)
    end
  end

  local reject = function(promise, reason)
    transition(promise, State.REJECTED, reason)
  end

  local fulfill = function(promise, value)
    transition(promise, State.FULFILLED, value)
  end

  transition = function(promise, state, value)
    if promise.state == state
        or promise.state ~= State.PENDING
        or ( state ~= State.FULFILLED and state ~= State.REJECTED )
        or value == nil
    then
      return
    end

    promise.state = state
    promise.value = value
    run(promise)
  end

  function Promise:next(on_fulfilled, on_rejected)
    local promise = Promise.new()

    table.insert(self.queue, {
      fulfill = is_callable(on_fulfilled) and on_fulfilled or nil,
      reject = is_callable(on_rejected) and on_rejected or nil,
      promise = promise
    })

    run(self)

    return promise
  end

  resolve = function(promise, x)
    if promise == x then
      reject(promise, 'TypeError: cannot resolve a promise with itself')
      return
    end

    local x_type = type(x)

    if x_type ~= 'table' then
      fulfill(promise, x)
      return
    end

    -- x is a promise in the current implementation
    if x.is_promise then
      -- 2.3.2.1 if x is pending, resolve or reject this promise after completion
      if x.state == State.PENDING then
        x:next(
          function(value)
            resolve(promise, value)
          end,
          function(reason)
            reject(promise, reason)
          end
        )
        return
      end
      -- if x is not pending, transition promise to x's state and value
      transition(promise, x.state, x.value)
      return
    end

    local called = false
    -- 2.3.3.1. Catches errors thrown by __index metatable
    local success, reason = pcall(function()
      local next = x.next
      if is_callable(next) then
        next(
          x,
          function(y)
            if not called then
              resolve(promise, y)
              called = true
            end
          end,
          function(r)
            if not called then
              reject(promise, r)
              called = true
            end
          end
        )
      else
        fulfill(promise, x)
      end
    end)

    if not success then
      if not called then
        reject(promise, reason)
      end
    end
  end

  run = function(promise)
    if promise.state == State.PENDING then return end

    do_async(function()
      while true do
        local obj = table.remove(promise.queue, 1)
        if not obj then
          break
        end

        local success, result = pcall(function()
          local success = obj.fulfill or passthrough
          local failure = obj.reject or errorthrough
          local callback = promise.state == State.FULFILLED and success or failure
          return callback(promise.value)
        end)

        if not success then
          reject(obj.promise, result)
        else
          resolve(obj.promise, result)
        end
      end
    end)
  end

  function Promise.new(callback)
    local instance = {
      queue = {}
    }
    setmetatable(instance, Promise.mt)

    if callback then
      callback(
        function(value)
          resolve(instance, value)
        end,
        function(reason)
          reject(instance, reason)
        end
      )
    end

    return instance
  end

  function Promise:catch(callback)
    return self:next(nil, callback)
  end

  function Promise:resolve(value)
    fulfill(self, value)
  end

  function Promise:reject(reason)
    reject(self, reason)
  end

  function Promise.update()
    while true do
      local async = table.remove(queue, 1)

      if not async then
        break
      end

      async()
    end
  end

  -- resolve when all promises complete
  function Promise.all(...)
    local promises = {...}
    local results = {}
    local state = State.FULFILLED
    local remaining = #promises

    local promise = Promise.new()

    local check_finished = function()
      if remaining > 0 then
        return
      end
      transition(promise, state, results)
    end

    for i,p in ipairs(promises) do
      p:next(
        function(value)
          results[i] = value
          remaining = remaining - 1
          check_finished()
        end,
        function(value)
          results[i] = value
          remaining = remaining - 1
          state = State.REJECTED
          check_finished()
        end
      )
    end

    check_finished()

    return promise
  end

  -- resolve with first promise to complete
  function Promise.race(...)
    local promises = {...}
    local promise = Promise.new()

    Promise.all(...):next(nil, function(value)
      reject(promise, value)
    end)

    local success = function(value)
      fulfill(promise, value)
    end

    for _,p in ipairs(promises) do
      p:next(success)
    end

    return promise
  end

  return Promise
end)
package.preload['love-update.thread'] = (function (...)
  require('love.timer')

  local request = require('love-update.vendor.luajit-request')

  local request_args = function(headers)
    local defaults = {
      timeout = 15,
      headers = {
        ["User-Agent"] = 'LÖVE Launcher'
      }
    }

    headers = type(headers) == 'table' and headers or {}

    for k,v in pairs(headers) do
      defaults.headers[k] = v
    end

    return defaults
  end

  local send_request = function(url, args)
    if not url then
      return false, 'Cannot fetch the latest version without a URL'
    end

    local response = request.send(url, args)

    if not response then
      return false, 'Could not request data from url: ' .. url
    end

    local code = tonumber(response.code)
    if not (code >= 200 and code < 300) then
      local result = string.format("Made a request to url ( %s ) and received a respons code of ( %d )", url, response.code)
      result = result .. "\n\n" .. response.body
      return false, result
    end

    return true, response.body
  end

  local throttle_progress = function(progress_id, channel)
    if not progress_id then
      return
    end

    local last_time
    local last_total = 0
    local updates = 30

    local smoothing = 0.1
    local average_speed = 0

    return function(dl_total, dl_current)
      if not last_time then
        last_time = love.timer.getTime()
      end

      local now = love.timer.getTime()

      local time_diff = now - last_time

      -- throttle status updates
      if time_diff < 1/updates then
        return
      end

      local dl_diff = dl_current - last_total
      local current_speed = dl_diff/time_diff

      last_total = dl_current
      last_time = now

      average_speed = smoothing * current_speed + (1-smoothing) * average_speed

      local percent = dl_total > 0 and dl_current / dl_total or 0

      channel:push({
        progress_id,
        'success',
        dl_total,
        dl_current,
        percent,
        average_speed
      })
    end
  end

  local tasks = {
    DOWNLOAD = function(complete_id, data, channel)
      local args = request_args()
      local progress_id, url = data.progress_id, data.url

      args.transfer_info_callback = throttle_progress(progress_id, channel)
      return send_request(url, args)
    end
  }

  --worker loop
  local update_loop = function(work_channel, response_channel)
    while true do
      local data = work_channel:demand()
      if data and type(data) == 'table' then
        local id, job = data.id, data.job

        data.id=nil
        data.job=nil

        if job == 'QUIT' then
          break
        end

        local task = tasks[job]

        if task then
          local success, result = task(id, data, response_channel)

          response_channel:push({
            id,
            success,
            result
          })
        end
      else
        print('Received invalid worker data')
      end
    end
  end

  return update_loop
end)
local foreground, work_channel, response_channel = unpack({...})

if foreground == false then
  require('love.filesystem')

  local work = require('love-update.thread')
  work(work_channel, response_channel)

  return
end

local work_channel = love.thread.getChannel('updater_work')
local response_channel = love.thread.getChannel('updater_response')

local file = foreground:gsub("%.", "/")
local thread_path = love.filesystem.isFile(file .. ".lua") and file .. ".lua" or file .. "/init.lua"

local noop = function() end

local Promise = require('love-update.vendor.promise')
local loaded_modules = {'main', 'conf', 'love-update.vendor.promise'}

local threads

-- Callback handler
local Callbacks = {
  _last_id = 0,
  list = {},
}

function Callbacks:nextId()
  self._last_id = self._last_id + 1
  return self._last_id
end

function Callbacks:add(callback)
  local id = self:nextId()

  self.list[id] = callback

  return id
end

function Callbacks:call(id, success, ...)
  local resolution = success and 'resolve' or 'reject'
  local callback = self:get(id)

  if type(callback) == 'table' and callback.is_promise then
    callback[resolution](callback, ...)
  elseif type(callback) == 'function' then
    callback(...)
  end
end

function Callbacks:get(id)
  return self.list[id] or noop
end

-- Worker instance
local Worker = {
  path = thread_path,
  work_channel = work_channel,
  response_channel = response_channel
}

function Worker:init()
  if not threads then
    threads = {}

    for i=1, 3 do
      local thread = love.thread.newThread(self.path)
      thread:start(false, self.work_channel, self.response_channel)
      table.insert(threads, thread)
    end
  end
end

function Worker:add(job)
  self:init()
  self.work_channel:push(job)
end

function Worker:shutdown()
  if threads then
    for i=1, #threads do
      self.work_channel:push({job = 'QUIT'})
    end
    threads = nil
  end
end

-- Updater/Launcher instance
local Launcher = {
  threads = 1
}

local function save_content(filename)
  return function(result)
    if not love.filesystem.write(filename, result) then
      error("Unable to save file " .. filename)
    end
    return filename
  end
end

function Launcher.fetch(url)
  local promise = Promise.new()

  Worker:add({
    job = 'DOWNLOAD',
    id = Callbacks:add(promise),
    url = url
  })

  return promise
end

function Launcher.download(url, filename, progress_callback)
  local promise = Promise.new()

  Worker:add({
    job = 'DOWNLOAD',
    id = Callbacks:add(promise),
    progress_id = Callbacks:add(progress_callback),
    url = url,
  })

  return promise:next(save_content(filename))
end

function Launcher.download_multiple(...)
  local promises = {}

  for i,v in ipairs({...}) do
    assert(v.url, 'Url is required')
    assert(v.filename, 'Filename is required')

    local promise = Launcher.download(v.url, v.filename)
    table.insert(promises, promise)
  end

  return Promise.all(promises)
end

function Launcher.update()
  local messages = response_channel:getCount()

  for i=1,messages do
    local data = response_channel:pop()
    if data then
      Callbacks:call(unpack(data))
    end
  end

  Promise.update()
end

function Launcher.launch(app, args)
  if not app then
    app = 'app.love'
  end

  if not Launcher.can_launch(app) then
    error('Unable to launch ' .. app)
  end

  love.filesystem.mount(app, "")

  for i,module_name in ipairs(loaded_modules) do
    package.loaded[module_name] = nil
  end

  Worker:shutdown()

  love.conf = nil
  love.init()
  love.load(args)
end

function Launcher.can_launch(app)
  return love.filesystem.isFile(app)
end

return Launcher
