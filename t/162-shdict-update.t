# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

#no_diff();
no_long_string();
#master_on();
#workers(2);

run_tests();

__DATA__

=== TEST 1: string key, set new int value
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            local succ, err, forcible = dogs:update("foo", function(old_val)
              ngx.say(old_val, " ", type(old_val))
              return false, 32
            end)
            ngx.say(succ, " ", err, " ", forcible)
            succ, err, forcible = dogs:update("bah", function(old_val)
              ngx.say(old_val, " ", type(old_val))
              return false, 10502
            end)
            ngx.say(succ, " ", err, " ", forcible)
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val))
            val = dogs:get("bah")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
nil nil
updated nil false
nil nil
updated nil false
32 number
10502 number
--- no_error_log
[error]



=== TEST 2: string key, update int value calculated from old value
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            local succ, err, forcible = dogs:update("foo", function(old_val)
              ngx.say(old_val, " ", type(old_val))
              return false, old_val * 2
            end)
            ngx.say(succ, " ", err, " ", forcible)
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
32 number
updated nil false
64 number
--- no_error_log
[error]



=== TEST 3: string key, remove int value
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            local succ, err, forcible = dogs:update("foo", function(old_val)
              ngx.say(old_val, " ", type(old_val))
              return false, nil
            end)
            ngx.say(succ, " ", err, " ", forcible)
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
32 number
removed nil false
nil nil
--- no_error_log
[error]



=== TEST 4: string key, update dictionary only if key does not exist (like add)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            local succ, err, forcible = dogs:update("foo", function(old_val)
              ngx.say(old_val, " ", type(old_val))
              if old_val ~= nil then
                  return true, nil
              end
              return false, 32
            end)
            ngx.say(succ, " ", err, " ", forcible)
            succ, err, forcible = dogs:update("foo", function(old_val)
              ngx.say(old_val, " ", type(old_val))
              if old_val ~= nil then
                  return true, nil
              end
              return false, 33
            end)
            ngx.say(succ, " ", err, " ", forcible)
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
nil nil
updated nil false
32 number
canceled nil false
32 number
--- no_error_log
[error]



=== TEST 5: string key, update dictionary only if key does exist (like replace)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            local succ, err, forcible = dogs:update("foo", function(old_val)
              ngx.say(old_val, " ", type(old_val))
              if old_val == nil then
                  return true, nil
              end
              return false, 32
            end)
            ngx.say(succ, " ", err, " ", forcible)
            dogs:set("foo", 33)
            succ, err, forcible = dogs:update("foo", function(old_val)
              ngx.say(old_val, " ", type(old_val))
              if old_val == nil then
                  return true, nil
              end
              return false, 34
            end)
            ngx.say(succ, " ", err, " ", forcible)
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
nil nil
canceled nil false
33 number
updated nil false
34 number
--- no_error_log
[error]



=== TEST 6: string key, update expired int value
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32, 0.01)
            ngx.sleep(0.02)
            local succ, err, forcible = dogs:update("foo", function(old_val)
              ngx.say(old_val, " ", type(old_val))
              return false, 33
            end)
            ngx.say(succ, " ", err, " ", forcible)
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
nil nil
updated nil false
33 number
--- no_error_log
[error]



=== TEST 7: string key, update dictionary only if value is not modified by others
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            local my_old_val = dogs:get("foo")
            local succ, err, forcible = dogs:update("foo", function(old_val)
              ngx.say(old_val, " ", type(old_val))
              if old_val ~= my_old_val then
                  return true, nil
              end
              return false, 33
            end)
            ngx.say(succ, " ", err, " ", forcible)
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val))

            dogs:set("foo", 34)
            my_old_val = dogs:get("foo")
            -- pretend to modify value by others.
            dogs:set("foo", 35)
            succ, err, forcible = dogs:update("foo", function(old_val)
              ngx.say(old_val, " ", type(old_val))
              if old_val ~= my_old_val then
                  return true, nil
              end
              return false, 36
            end)
            ngx.say(succ, " ", err, " ", forcible)
            val = dogs:get("foo")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
32 number
updated nil false
33 number
35 number
canceled nil false
35 number
--- no_error_log
[error]



=== TEST 7: string key, return some error
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            local succ, err, forcible = dogs:update("foo", function(old_val)
              ngx.say(old_val, " ", type(old_val))
              return nil, "my error"
            end)
            ngx.say(succ, " ", err, " ", forcible)
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
32 number
nil my error nil
32 number
--- no_error_log
[error]
