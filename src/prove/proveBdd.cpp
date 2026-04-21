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
#include <map>
#include <vector>

#include "cirGate.h"
#include "cirMgr.h"
#include "util.h"

using namespace std;
using namespace gv::cir;

extern CirMgr* cirMgr;

void BddMgrV::buildPInitialState() {
    // Reset proof bookkeeping each time PINITialstate is called.
    _isFixed = false;
    _reachStates.clear();

    // Assumption: all latch current-state bits are initialized to 0.
    _initState = BddNodeV::_one;
    for (unsigned i = 0, n = cirMgr->getNumLATCHs(); i < n; ++i) {
        CirRoGate* ro = cirMgr->getRo(i);
        BddNodeV xVar = getBddNodeV(ro->getGid());
        assert(xVar() != 0);
        _initState &= ~xVar;
    }

    _reachStates.push_back(_initState);
}

void BddMgrV::buildPTransRelation() {
    // tri(x, i, y) = /\_k (y_k <-> delta_k(x, i))
    _tri = BddNodeV::_one;
    for (unsigned k = 0, n = cirMgr->getNumLATCHs(); k < n; ++k) {
        CirRiGate* ri = cirMgr->getRi(k);
        BddNodeV yVar = getBddNodeV(ri->getName());    // next-state support
        BddNodeV fx   = getBddNodeV(ri->getGid());     // next-state function
        assert(yVar() != 0 && fx() != 0);
        _tri &= ~(yVar ^ fx);
    }

    // tr(x, y) = exists input . tri(x, input, y)
    _tr = _tri;
    for (unsigned i = 0, n = cirMgr->getNumPIs(); i < n; ++i) {
        CirPiGate* pi = cirMgr->getPi(i);
        BddNodeV in   = getBddNodeV(pi->getGid());
        assert(in() != 0);
        _tr = _tr.exist(in.getLevel());
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
    if (_reachStates.empty()) _reachStates.push_back(_initState);
    _isFixed = false;

    for (int t = 0; t < level; ++t) {
        const BddNodeV curReach = _reachStates.back();
        const BddNodeV nextNs   = find_ns(curReach);      // in Y-space
        const BddNodeV nextCs   = ns_to_cs(nextNs);       // renamed to X-space
        const BddNodeV allReach = curReach | nextCs;
        if (allReach == curReach) {
            _isFixed = true;
            cout << "Fixed point is reached (time : " << (t + 1) << ")" << endl;
            return;
        }
        _reachStates.push_back(allReach);
    }
}

void BddMgrV::runPCheckProperty(const string& name, BddNodeV monitor) {
    // Reachability set is represented over current-state vars only.
    // Quantify out PI vars from monitor before intersection.
    for (unsigned i = 0, n = cirMgr->getNumPIs(); i < n; ++i) {
        CirPiGate* pi = cirMgr->getPi(i);
        BddNodeV in   = getBddNodeV(pi->getGid());
        assert(in() != 0);
        monitor = monitor.exist(in.getLevel());
    }

    const BddNodeV bad = getPReachState() & monitor;
    if (bad == BddNodeV::_zero)
        cout << "Monitor \"" << name << "\" is safe." << endl;
    else
        cout << "Monitor \"" << name << "\" is violated." << endl;
}

BddNodeV
BddMgrV::find_ns(BddNodeV cs) {
    // Image in Y-space:
    //   NS(Y) = exists X . (TR(X, Y) & CS(X))
    BddNodeV img = _tr & cs;
    for (unsigned i = 0, n = cirMgr->getNumLATCHs(); i < n; ++i) {
        CirRoGate* ro = cirMgr->getRo(i);
        BddNodeV xVar = getBddNodeV(ro->getGid());
        assert(xVar() != 0);
        img = img.exist(xVar.getLevel());
    }
    return img;
}

BddNodeV
BddMgrV::ns_to_cs(BddNodeV ns) {
    // Rename Y -> X via Shannon expansion, with memoization.
    map<unsigned, BddNodeV> y2x;
    for (unsigned i = 0, n = cirMgr->getNumLATCHs(); i < n; ++i) {
        BddNodeV yVar = getBddNodeV(cirMgr->getRi(i)->getName());
        BddNodeV xVar = getBddNodeV(cirMgr->getRo(i)->getGid());
        assert(yVar() != 0 && xVar() != 0);
        y2x[yVar.getLevel()] = xVar;
    }

    map<size_t, size_t> cache;
    function<BddNodeV(const BddNodeV&)> renameRec = [&](const BddNodeV& f) -> BddNodeV {
        if ((f == BddNodeV::_zero) || (f == BddNodeV::_one)) return f;
        map<size_t, size_t>::iterator it = cache.find(f());
        if (it != cache.end()) return BddNodeV(it->second);

        const unsigned lv = f.getLevel();
        const BddNodeV t  = renameRec(f.getLeftCofactor(lv));
        const BddNodeV e  = renameRec(f.getRightCofactor(lv));

        BddNodeV var = getSupport(lv);  // keep variable by default
        map<unsigned, BddNodeV>::iterator yit = y2x.find(lv);
        if (yit != y2x.end()) var = yit->second;  // substitute Y with X

        const BddNodeV r = (var & t) | ((~var) & e);
        cache[f()]       = r();
        return r;
    };

    return renameRec(ns);
}
