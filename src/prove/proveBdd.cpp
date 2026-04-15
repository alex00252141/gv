/****************************************************************************
  FileName     [ proveBdd.cpp ]
  PackageName  [ prove ]
  Synopsis     [ For BDD-based verification ]
  Author       [ ]
  Copyright    [ Copyright(c) 2023-present DVLab, GIEE, NTU, Taiwan ]
****************************************************************************/

#include "bddMgrV.h"
#include "gvMsg.h"
// #include "gvNtk.h"
#include <iomanip>
#include <iostream>
#include <vector>

#include "cirGate.h"
#include "cirMgr.h"
#include "util.h"

void BddMgrV::buildPInitialState() {
    // Reset proof progress whenever initial state is rebuilt.
    _isFixed = false;
    _reachStates.clear();

    // Initial state = all current-state bits are 0.
    _initState = BddNodeV::_one;
    for (unsigned i = 0, n = cirMgr->getNumLATCHs(); i < n; ++i) {
        const BddNodeV cs = getBddNodeV(cirMgr->getRo(i)->getGid());
        if (cs() == 0) {
            gvMsg(GV_MSG_ERR)
                << "Current-state BDD is Not Yet Constructed for latch " << i
                << " !!" << endl;
            _initState = BddNodeV::_zero;
            return;
        }
        _initState &= ~cs;
    }
}

void BddMgrV::buildPTransRelation() {
    // Reset proof progress whenever transition relation is rebuilt.
    _isFixed = false;
    _reachStates.clear();

    // TRI(Y, X, I) = /\_i (Y_i <-> delta_i(X, I))
    _tri = BddNodeV::_one;
    for (unsigned i = 0, n = cirMgr->getNumLATCHs(); i < n; ++i) {
        const BddNodeV nsVar = getBddNodeV(cirMgr->getRi(i)->getName());
        const BddNodeV nsFun = getBddNodeV(cirMgr->getRi(i)->getGid());
        if (nsVar() == 0 || nsFun() == 0) {
            gvMsg(GV_MSG_ERR)
                << "Next-state BDD is Not Yet Constructed for latch " << i
                << " !!" << endl;
            _tri = BddNodeV::_zero;
            _tr  = BddNodeV::_zero;
            return;
        }
        _tri &= (nsVar & nsFun) | (~nsVar & ~nsFun);
    }

    // TR(Y, X) = \exists I . TRI(Y, X, I)
    _tr = _tri;
    for (unsigned i = 0, n = cirMgr->getNumPIs(); i < n; ++i) {
        const BddNodeV pi = getBddNodeV(cirMgr->getPi(i)->getGid());
        if (pi() != 0) _tr = _tr.exist(pi.getLevel());
    }
}

BddNodeV BddMgrV::restrict(const BddNodeV& f, const BddNodeV& g) {
    if (g == BddNodeV::_zero) {
        cout << "Error in restrict!!" << endl;
    }
    if (g == BddNodeV::_one) {
        return f;
    }
    if (f == BddNodeV::_zero || f == BddNodeV::_one) {
        return f;
    }
    unsigned a = g.getLevel();
    if (g.getLeftCofactor(a) == BddNodeV::_zero) {
        return restrict(f.getRightCofactor(a), g.getRightCofactor(a));
    }
    if (g.getRightCofactor(a) == BddNodeV::_zero) {
        return restrict(f.getLeftCofactor(a), g.getLeftCofactor(a));
    }
    if (f.getLeftCofactor(a) == f.getRightCofactor(a)) {
        return restrict(f, g.getLeftCofactor(a) | g.getRightCofactor(a));
    }
    BddNodeV newNode =
        (~getSupport(a)& restrict(f.getRightCofactor(a),
                                  g.getRightCofactor(a))) |
        (getSupport(a)& restrict(f.getLeftCofactor(a), g.getLeftCofactor(a)));
    return newNode;
}

void BddMgrV::buildPImage(int level) {
    // _reachStates[t] stores cumulative reachable states up to time t.
    if (_reachStates.empty()) _reachStates.push_back(_initState);

    for (int i = 0; i < level; ++i) {
        if (_isFixed) break;

        const BddNodeV curReach = _reachStates.back();
        const BddNodeV nextNs   = find_ns(curReach);
        const BddNodeV nextCs   = ns_to_cs(nextNs);
        const BddNodeV newReach = curReach | nextCs;

        if (newReach == curReach) {
            _isFixed = true;
            const size_t fpTime =
                (_reachStates.empty()) ? 0 : (_reachStates.size() - 1);
            cout << "Fixed point is reached (time : " << fpTime
                 << ")" << endl;
            break;
        }
        _reachStates.push_back(newReach);
    }
}

void BddMgrV::runPCheckProperty(const string& name, BddNodeV monitor) {
    // Check AG(~monitor): violation iff monitor intersects reachable states.
    for (unsigned i = 0, n = cirMgr->getNumPIs(); i < n; ++i) {
        const BddNodeV pi = getBddNodeV(cirMgr->getPi(i)->getGid());
        if (pi() != 0) monitor = monitor.exist(pi.getLevel());
    }

    const BddNodeV bad = getPReachState() & monitor;
    if (bad == BddNodeV::_zero) {
        if (_isFixed) {
            cout << "Monitor \"" << name << "\" is safe." << endl;
        } else {
            const size_t time =
                (_reachStates.empty()) ? 0 : (_reachStates.size() - 1);
            cout << "Monitor \"" << name << "\" is safe up to time " << time
                 << "." << endl;
        }
        return;
    }

    cout << "Monitor \"" << name << "\" is violated." << endl;
    cout << "Counter Example:" << endl;

    // Find earliest timeframe that can hit a bad state.
    size_t badTime = 0;
    for (size_t t = 0; t < _reachStates.size(); ++t) {
        if ((_reachStates[t] & bad) != BddNodeV::_zero) {
            badTime = t;
            break;
        }
    }

    vector<BddNodeV> trace(badTime + 1, BddNodeV::_zero);
    trace[badTime] = (_reachStates[badTime] & bad).getCube();

    // Backtrack one predecessor state at a time.
    for (size_t t = badTime; t > 0; --t) {
        BddNodeV targetY = trace[t];
        if (targetY != BddNodeV::_one && targetY != BddNodeV::_zero &&
            cirMgr->getNumLATCHs() > 0) {
            const unsigned nPi   = cirMgr->getNumPIs();
            const unsigned nLatch = cirMgr->getNumLATCHs();
            bool moved            = false;
            targetY = targetY.nodeMove(nPi + 1, nPi + nLatch + 1, moved);
            if (!moved) {
                // Fallback: keep targetY unchanged if conversion fails.
            }
        }

        BddNodeV pred = _tr & targetY;
        for (unsigned i = 0, n = cirMgr->getNumLATCHs(); i < n; ++i) {
            const BddNodeV nsVar = getBddNodeV(cirMgr->getRi(i)->getName());
            if (nsVar() != 0) pred = pred.exist(nsVar.getLevel());
        }
        pred &= _reachStates[t - 1];

        if (pred == BddNodeV::_zero)
            trace[t - 1] = _reachStates[t - 1].getCube();
        else
            trace[t - 1] = pred.getCube();
    }

    for (size_t t = 0; t <= badTime; ++t) {
        string bits = "";
        for (int i = int(cirMgr->getNumLATCHs()) - 1; i >= 0; --i) {
            const BddNodeV cs = getBddNodeV(cirMgr->getRo(i)->getGid());
            if (cs() == 0) {
                bits += 'x';
                continue;
            }
            const BddNodeV pos = trace[t].getLeftCofactor(cs.getLevel());
            const BddNodeV neg = trace[t].getRightCofactor(cs.getLevel());
            if (pos == BddNodeV::_zero && neg != BddNodeV::_zero)
                bits += '0';
            else if (neg == BddNodeV::_zero && pos != BddNodeV::_zero)
                bits += '1';
            else
                bits += '0';
        }
        cout << t << ": " << bits << endl;
    }
}

BddNodeV
BddMgrV::find_ns(BddNodeV cs) {
    // Compute image in next-state variable space:
    // NS(Y) = \exists X . (TR(Y, X) /\ CS(X))
    BddNodeV ns = _tr & cs;
    for (unsigned i = 0, n = cirMgr->getNumLATCHs(); i < n; ++i) {
        const BddNodeV csVar = getBddNodeV(cirMgr->getRo(i)->getGid());
        if (csVar() != 0) ns = ns.exist(csVar.getLevel());
    }
    return ns;
}

BddNodeV
BddMgrV::ns_to_cs(BddNodeV ns) {
    // Rename NS variables (Y) back to CS variables (X) by level movement.
    if (ns == BddNodeV::_one || ns == BddNodeV::_zero) return ns;
    if (cirMgr->getNumLATCHs() == 0) return ns;

    const unsigned nPi    = cirMgr->getNumPIs();
    const unsigned nLatch = cirMgr->getNumLATCHs();
    bool moved            = false;
    BddNodeV cs           = ns.nodeMove(nPi + nLatch + 1, nPi + 1, moved);
    return moved ? cs : ns;
}
