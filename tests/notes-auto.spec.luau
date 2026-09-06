return function(newLoop, valid)
    local passed = 0
    local function test(name, fn) fn(); passed += 1; print("PASS notes batch " .. name) end
    local function fixture()
        local f = { time = 0, count = 3500, identity = {}, amounts = {}, confirms = 0 }
        f.context = { accountId = 12, gameId = 34, placeId = 6473861193, jobId = "server", slot = "A", actor = {} }
        f.adapter = { now = function() return f.time end, context = function() return table.clone(f.context) end,
            cancel = function() f.cancelled = true end, uncertain = function() f.locked = true end,
            status = function(s) f.state = s; if f.onStatus then f.onStatus(s) end end,
            sleep = function(s) f.time += s; if f.onSleep then f.onSleep() end end,
            preflight = function() return true end, ready = function() return true end,
            balance = function() return f.count, f.identity end,
            confirmed = function() f.confirms += 1 end,
            drop = function(limit)
                local amount = math.min(limit, f.count); table.insert(f.amounts, amount)
                f.count -= amount; return true, "sent", amount
            end }
        f.loop = newLoop(f.adapter); return f
    end
    test("MAX 3500 drains 1000 1000 1000 500 without any travel adapter", function()
        local f = fixture(); local ok, why = f.loop:run()
        assert(ok and why == "empty" and f.count == 0 and f.confirms == 4 and f.time >= 3)
        assert(table.concat(f.amounts, ",") == "1000,1000,1000,500" and not f.loop.active)
    end)
    test("5000 with 3500 clips the total to the actual balance", function()
        local f = fixture(); assert(f.loop:run(5000)); assert(table.concat(f.amounts, ",") == "1000,1000,1000,500")
    end)
    test("requested 2500 leaves the remaining 1000 untouched", function()
        local f = fixture(); local ok, why = f.loop:run(2500)
        assert(ok and why == "complete" and f.count == 1000 and table.concat(f.amounts, ",") == "1000,1000,500")
    end)
    test("553 and zero are exact without extra submissions", function()
        local f = fixture(); f.count = 553; assert(f.loop:run()); assert(#f.amounts == 1 and f.amounts[1] == 553)
        f = fixture(); f.count = 0; assert(f.loop:run()); assert(#f.amounts == 0)
    end)
    test("invalid totals and balances send nothing", function()
        for _, n in ipairs({ -1, 0, 1.2, math.huge, "553", 1000000001 }) do
            local f = fixture(); assert(not f.loop:run(n)); assert(#f.amounts == 0)
        end
        for _, n in ipairs({ -1, 1.2, math.huge, "553" }) do
            local f = fixture(); f.count = n; assert(not f.loop:run()); assert(#f.amounts == 0)
        end
        local f = fixture(); f.count = nil; assert(not f.loop:run()); assert(#f.amounts == 0)
    end)
    test("no observed decrement stops after exactly one submission", function()
        local f = fixture(); f.adapter.drop = function() table.insert(f.amounts, 1000); return true, "sent", 1000 end
        assert(not f.loop:run()); assert(#f.amounts == 1 and f.locked and f.time >= 10)
    end)
    test("another source or unexpected balance is not confirmation", function()
        for _, mode in ipairs({ "source", "amount", "missing-source" }) do
            local f = fixture(); f.adapter.drop = function()
                f.count -= mode == "amount" and 999 or 1000
                if mode == "source" then f.identity = {} elseif mode == "missing-source" then f.identity = nil end
                return true, "sent", 1000
            end
            assert(not f.loop:run()); assert(f.locked)
        end
    end)
    test("Stop during confirmation prevents another batch and locks the unknown outcome", function()
        local f = fixture(); f.adapter.drop = function() table.insert(f.amounts, 1000); return true, "sent", 1000 end
        f.onSleep = function() f.loop:stop() end
        assert(not f.loop:run()); assert(#f.amounts == 1 and f.locked)
    end)
    test("Stop between confirmed batches prevents the second without locking", function()
        local f = fixture(); f.onSleep = function() f.loop:stop() end
        assert(not f.loop:run()); assert(#f.amounts == 1 and not f.locked)
    end)
    test("balance changes between batches stop", function()
        local f = fixture(); f.onSleep = function() f.count = 4000 end
        assert(not f.loop:run()); assert(#f.amounts == 1 and not f.locked)
    end)
    test("already-used dialog must close before the next batch", function()
        local f = fixture(); f.adapter.ready = function() return #f.amounts == 0 end
        assert(not f.loop:run()); assert(#f.amounts == 1 and f.state == "prompt-not-closed")
    end)
    test("fresh dialogs can arrive after a delay", function()
        local f = fixture(); f.count = 1500
        f.adapter.ready = function() return #f.amounts == 0 or f.time > 2 end
        assert(f.loop:run()); assert(#f.amounts == 2 and f.count == 0)
    end)
    test("changed account game place slot server or character cancels", function()
        for _, field in ipairs({ "accountId", "gameId", "placeId", "jobId", "slot", "actor" }) do
            local f = fixture()
            f.onSleep = function() f.context[field] = field == "actor" and {} or "changed" end
            assert(not f.loop:run()); assert(#f.amounts == 1)
        end
    end)
    test("preflight failure sends nothing", function()
        local f = fixture(); f.adapter.preflight = function() return false, "blocked" end
        assert(not f.loop:run()); assert(#f.amounts == 0)
    end)
    test("valid saved setting is per account and game with no expiry", function()
        local c = { accountId = 12, gameId = 34 }
        local r = { version = 2, enabled = true, pending = false, token = "unique-token-123456789", accountId = 12, gameId = 34 }
        assert(valid(r, c)); r.accountId = 13; assert(not valid(r, c)); r.accountId = 12
        r.gameId = 35; assert(not valid(r, c)); r.gameId = 34
        r.pending = nil; assert(not valid(r, c)); r.pending = false; r.version = 1; assert(not valid(r, c))
    end)
    test("lower live prompt cap progresses toward the same requested total", function()
        local f = fixture(); f.adapter.drop = function(limit)
            local n = math.min(400, limit); f.count -= n; table.insert(f.amounts, n); return true, "sent", n
        end
        assert(f.loop:run(1000)); assert(table.concat(f.amounts, ",") == "400,400,200" and f.count == 2500)
    end)
    print(passed .. " notes batch tests passed")
end
