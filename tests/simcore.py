import lupa.lua51 as L, sys
import os
HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(HERE, "..", "EPUGuild").replace(os.sep, "/")
ROSTER = [("Chris Baker","Officer",1),("Tyler Baker","Member",3),("Epu Bank","Bank",4),("Newbie Stone","Initiate",4),("Chris Stone","Member",3),("Pip Baker","Member",3)]

class Client:
    def __init__(self, name):
        self.rt = L.LuaRuntime(unpack_returned_tuples=True)
        self.name = name
        self.rt.execute(open(os.path.join(HERE, "stubs.lua")).read())
        rank = [r for r in ROSTER if r[0]==name][0]
        g = self.rt.globals()
        self.rt.execute('__name, __rankName, __rankIndex = "%s", "%s", %d' % (name, rank[1], rank[2]))
        self.rt.execute("__roster = {" + ",".join('{"%s","%s",%d}'%r for r in ROSTER) + "}")
        self.rt.execute(f'__load("{ADDON}")')
    def ex(self, code): return self.rt.execute(code)
    def ev(self, code): return self.rt.eval(code)

clients = {}
def route():
    moved = True
    while moved:
        moved = False
        for c in list(clients.values()):
            out = c.ev("__out")
            msgs = [out[i] for i in range(1, len(out)+1)]
            c.ex("__out = {}")
            for m in msgs:
                moved = True
                p, msg, chan, tgt = m[1], m[2], m[3], m[4]
                for d in clients.values():
                    if d is c: continue
                    if chan == "WHISPER" and d.name != tgt: continue
                    d.rt.globals()["__fire"]("CHAT_MSG_ADDON", p, msg, chan, c.name)

def tick(sec, step=0.25):
    t = 0
    while t < sec:
        for c in clients.values(): c.ex(f"__advance({step})")
        route(); t += step

def check(label, cond):
    print(("PASS " if cond else "FAIL ") + label)
    if not cond: check.failed += 1
check.failed = 0

