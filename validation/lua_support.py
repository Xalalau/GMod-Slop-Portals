"""Explicit Lua 5.4 test adapter, NOT a Garry's Mod emulator or native GLua compiler."""
import ctypes
import ctypes.util
import re

# Existing source uses ordinary short strings and -- comments. Preserve long strings/comments too.
TOKENS = re.compile(r'--\[(=*)\[.*?\]\1\]|--[^\n]*|\[(=*)\[.*?\]\2\]|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|!=|!|&&|\|\||\bcontinue\b', re.S)

def normalize(source: str, syntax_only: bool = False) -> str:
    def replace(match):
        token = match[0]
        if token == 'continue':
            if not syntax_only:
                raise ValueError('Executable excerpt contains continue; select a smaller unmodified excerpt')
            # A syntactic stand-in only; deliberately NEVER execute this transformed branch.
            return 'do break end'
        return {'!=': '~=', '!': 'not ', '&&': ' and ', '||': ' or '}.get(token, token)
    return TOKENS.sub(replace, source)

class Lua:
    def __init__(self):
        name = ctypes.util.find_library('lua5.4')
        if not name:
            raise RuntimeError('Lua 5.4 shared library is required (e.g. liblua5.4-0 on Debian)')
        self.lib = lib = ctypes.CDLL(name)
        lib.luaL_newstate.restype = ctypes.c_void_p
        lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
        lib.luaL_loadbufferx.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p, ctypes.c_char_p]
        lib.luaL_loadbufferx.restype = ctypes.c_int
        lib.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ssize_t, ctypes.c_void_p]
        lib.lua_pcallk.restype = ctypes.c_int
        lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
        lib.lua_tolstring.restype = ctypes.c_void_p
        lib.lua_close.argtypes = [ctypes.c_void_p]
    def check(self, code: str, execute: bool = False, name: str = 'patch-test') -> str:
        lib = self.lib
        state = lib.luaL_newstate()
        if not state:
            raise MemoryError('luaL_newstate failed')
        try:
            lib.luaL_openlibs(state)
            data = code.encode()
            status = lib.luaL_loadbufferx(state, data, len(data), ('@' + name).encode(), None)
            if not status and execute:
                status = lib.lua_pcallk(state, 0, 1, 0, 0, None)
            length = ctypes.c_size_t()
            ptr = lib.lua_tolstring(state, -1, ctypes.byref(length))
            text = ctypes.string_at(ptr, length.value).decode(errors='replace') if ptr else ''
            if status:
                raise RuntimeError(text)
            return text
        finally:
            lib.lua_close(state)
