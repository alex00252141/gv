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
    _isFixed = false;
    _reachStates.clear();

    _initState         = BddNodeV::_one;
    const unsigned nPi = cirMgr->getNumPIs();
    const unsigned nL  = cirMgr->getNumLATCHs();
    // Initialize all current-state latches to zero.
    for (unsigned i = 0; i < nL; ++i) {
        _initState &= ~getSupport(nPi + i + 1);
    }
}

void BddMgrV::buildPTransRelation() {
    _tr  = BddNodeV::_one;
    _tri = BddNodeV::_one;

    const unsigned nPi = cirMgr->getNumPIs();
    const unsigned nL  = cirMgr->getNumLATCHs();

    // Build TR(X, I, Y) = /\_k (y_k <-> delta_k(X, I)).
    for (unsigned i = 0; i < nL; ++i) {
        const BddNodeV nsVar = getSupport(nPi + nL + i + 1);
        const BddNodeV nsFun = getBddNodeV(cirMgr->getRi(i)->getGid());
        _tr &= ~(nsVar ^ nsFun);
    }

    // Build TRI(X, Y) = \E_I TR(X, I, Y).
    _tri = _tr;
    for (unsigned i = 1; i <= nPi; ++i) {
        _tri = _tri.exist(i);
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
    if (_isFixed) return;

    for (int t = 0; t < level; ++t) {
        const BddNodeV currentReach = _reachStates.back();
        const BddNodeV nsReach      = find_ns(currentReach);
        const BddNodeV nextReach    = ns_to_cs(nsReach);
        const BddNodeV unionReach   = currentReach | nextReach;

        if (unionReach == currentReach) {
            _isFixed = true;
            cout << "Fixed point is reached (time : " << (t + 1) << ")"
                 << endl;
            return;
        }
        _reachStates.push_back(unionReach);
    }
}

void BddMgrV::runPCheckProperty(const string& name, BddNodeV monitor) {
    // Convert monitor(I, X) to state-only bad set by existentially
    // quantifying all primary inputs.
    const unsigned nPi = cirMgr->getNumPIs();
    for (unsigned i = 1; i <= nPi; ++i) {
        monitor = monitor.exist(i);
    }

    const BddNodeV reachable = getPReachState();
    const BddNodeV bad       = reachable & monitor;

    if (bad == BddNodeV::_zero) {
        cout << "Monitor \"" << name << "\" is safe." << endl;
    } else {
        cout << "Monitor \"" << name << "\" is violated." << endl;
    }
}

BddNodeV
BddMgrV::find_ns(BddNodeV cs) {
    BddNodeV ns = _tri & cs;

    // Image over current-state variables:
    // NS(Y) = \E_X [TRI(X, Y) /\ Reach(X)].
    const unsigned nPi = cirMgr->getNumPIs();
    const unsigned nL  = cirMgr->getNumLATCHs();
    for (unsigned i = 0; i < nL; ++i) {
        ns = ns.exist(nPi + i + 1);
    }
    return ns;
}

BddNodeV
BddMgrV::ns_to_cs(BddNodeV ns) {
    const unsigned nPi = cirMgr->getNumPIs();
    const unsigned nL  = cirMgr->getNumLATCHs();

    // Substitute Y -> X by Shannon expansion on each Y_i:
    // F[X/Y] = (X_i & F[Y_i=1]) | (~X_i & F[Y_i=0]).
    for (unsigned i = 0; i < nL; ++i) {
        const unsigned csLevel = nPi + i + 1;
        const unsigned nsLevel = nPi + nL + i + 1;
        ns = (getSupport(csLevel) & ns.getLeftCofactor(nsLevel)) |
             (~getSupport(csLevel) & ns.getRightCofactor(nsLevel));
    }
    return ns;
}
