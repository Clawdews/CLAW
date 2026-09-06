return function(newLoop, valid)
    local passed = 0
    local function test(name, fn) fn(); passed += 1; print("PASS notes auto " .. name) end
    local function fixture()
        local f = { time = 1000, count = 4335, identity = {}, drops = 0, joins = 0, cleared = 0 }
        f.context = { accountId = 12, gameId = 34, placeId = 6473861193, jobId = "exact-server", slot = "A" }
        f.record = { version = 1, phase = "world", token = "test-token-123456789", accountId = 12, gameId = 34,
            worldPlaceId = 6473861193, jobId = "exact-server", slot = "A", cycles = 0, expires = 2800 }
        f.adapter = { now = function() return f.time end, context = function() return f.context end,
            cancel = function() f.cancelled = true end, clear = function() f.cleared += 1 end,
            status = function(s) f.state = s; if f.onStatus then f.onStatus(s) end end,
            uncertain = function() f.locked = true end,
            sleep = function(s) f.time += s; if f.onSleep then f.onSleep() end end,
            preflight = function() return true end,
            balance = function() return f.count, f.identity end,
            drop = function() f.drops += 1; local n = math.min(1000, f.count); f.count -= n; return true, "sent", n end,
            depart = function(r, live) assert(live()); f.next = r; f.joins += 1; return true end }
        f.loop = newLoop(f.adapter); return f
    end
    test("4335 drops 1000 then saves the same server and remaining balance", function()
        local f = fixture(); assert(f.loop:run(f.record)); assert(f.drops == 1 and f.joins == 1 and f.time >= 1003)
        assert(f.next.expectedBalance == 3335 and f.next.jobId == "exact-server" and f.next.slot == "A" and f.next.phase == "menu")
    end)
    test("553 drops 553 then stops without another rejoin", function()
        local f = fixture(); f.count = 553; local ok, s = f.loop:run(f.record)
        assert(ok and s == "empty" and f.count == 0 and f.joins == 0 and not f.loop.active)
    end)
    test("zero balance sends nothing", function() local f = fixture(); f.count = 0; f.loop:run(f.record); assert(f.drops == 0 and f.joins == 0) end)
    test("unreadable and invalid balances fail closed", function()
        for _, n in ipairs({ -1, 1.2, math.huge, "553" }) do
            local f = fixture(); f.count = n; assert(not f.loop:run(f.record)); assert(f.drops == 0)
        end
        local f = fixture(); f.count = nil; assert(not f.loop:run(f.record)); assert(f.drops == 0)
    end)
    test("returning balance must match the previously confirmed remainder", function()
        local f = fixture(); f.record.expectedBalance = 5000; assert(not f.loop:run(f.record)); assert(f.drops == 0)
    end)
    test("no observed decrement means no rejoin and locks another attempt", function()
        local f = fixture(); f.adapter.drop = function() f.drops += 1; return true, "sent", 1000 end
        assert(not f.loop:run(f.record)); assert(f.joins == 0 and f.drops == 1 and f.locked and f.time >= 1010)
    end)
    test("a different display object or an unexpected decrement is not confirmation", function()
        for _, mode in ipairs({ "source", "amount" }) do
            local f = fixture(); f.adapter.drop = function()
                if mode == "source" then f.identity = {} else f.count -= 999 end
                return true, "sent", 1000
            end
            assert(not f.loop:run(f.record)); assert(f.joins == 0 and f.locked)
        end
    end)
    test("Stop during confirmation prevents a later rejoin", function()
        local f = fixture(); f.adapter.drop = function() return true, "sent", 1000 end
        f.onSleep = function() f.loop:stop() end; assert(not f.loop:run(f.record)); assert(f.joins == 0 and f.locked)
    end)
    test("Stop during countdown prevents rejoining without locking a confirmed drop", function()
        local f = fixture(); f.onSleep = function() f.loop:stop() end
        assert(not f.loop:run(f.record)); assert(f.joins == 0 and not f.locked)
    end)
    test("balance change during countdown stops", function()
        local f = fixture(); f.onSleep = function() f.count = 4000 end
        assert(not f.loop:run(f.record)); assert(f.joins == 0)
    end)
    test("wrong account, slot, game, server or expired run sends nothing", function()
        for k, v in pairs({ accountId = 99, slot = "B", gameId = 99, jobId = "another", expires = 1000, phase = "menu", cycles = 100, worldPlaceId = 10 }) do
            local f = fixture(); f.record[k] = v; assert(not f.loop:run(f.record)); assert(f.drops == 0)
        end
    end)
    test("teleport failure and preflight failure are not retried", function()
        local f = fixture(); f.adapter.depart = function() f.joins += 1; return false end
        assert(not f.loop:run(f.record)); assert(f.joins == 1 and not f.loop.active)
        f = fixture(); f.adapter.preflight = function() return false, "queue unavailable" end
        assert(not f.loop:run(f.record)); assert(f.drops == 0)
    end)
    test("cycle ceiling stops after the confirmed hundredth drop", function()
        local f = fixture(); f.record.cycles = 99; local ok, s = f.loop:run(f.record)
        assert(ok and s == "cycle-limit" and f.joins == 0)
    end)
    test("same-account menu resume is accepted only in the menu", function()
        local f = fixture(); f.record.phase = "menu"; assert(not valid(f.record, f.time, f.context, "menu"))
        f.context.placeId = 4111023553; assert(valid(f.record, f.time, f.context, "menu"))
    end)
    test("live context loss before submit cancels", function()
        local f = fixture(); f.adapter.preflight = function() f.context.slot = "B"; return true end
        assert(not f.loop:run(f.record)); assert(f.drops == 0)
    end)
    print(passed .. " notes auto tests passed")
end
