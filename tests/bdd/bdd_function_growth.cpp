#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <random>
#include <string>
#include <unordered_set>
#include <utility>
#include <vector>

#include "bddMgrV.h"

using BddVec = std::vector<BddNodeV>;

namespace {

struct ExperimentConfig {
    bool dumpDot     = false;
    std::string dotDir;
};

struct AdderVars {
    BddVec a;
    BddVec b;
};

size_t
countNodesDfs(const BddNodeV& node, std::unordered_set<size_t>& visited) {
    const size_t nodeId = node() & BDD_NODE_PTR_MASKV;
    if (!visited.insert(nodeId).second) return 0;
    if (node.getLevel() == 0) return 1;
    countNodesDfs(node.getLeft(), visited);
    countNodesDfs(node.getRight(), visited);
    return 1;
}

size_t
countNodes(const BddVec& roots) {
    std::unordered_set<size_t> visited;
    visited.reserve(4096);
    for (const BddNodeV& root : roots)
        countNodesDfs(root, visited);
    return visited.size();
}

template <class BuildFn>
size_t
runExperiment(BuildFn&& buildFn) {
    return buildFn();
}

AdderVars
buildInterleavedAdderVars(int n, int maxSupports) {
    AdderVars vars;
    vars.a.resize(n);
    vars.b.resize(n);
    for (int i = 0; i < n; ++i) {
        // Top variable order: a0, b0, a1, b1, ...
        vars.a[i] = bddMgrV->getSupport(static_cast<size_t>(maxSupports - (2 * i)));
        vars.b[i] = bddMgrV->getSupport(static_cast<size_t>(maxSupports - (2 * i + 1)));
    }
    return vars;
}

BddVec
addWords(const BddVec& lhs, const BddVec& rhs) {
    const size_t n = std::max(lhs.size(), rhs.size());
    BddVec sum;
    sum.reserve(n + 1);

    BddNodeV carry = BddNodeV::_zero;
    for (size_t i = 0; i < n; ++i) {
        const BddNodeV a = (i < lhs.size()) ? lhs[i] : BddNodeV::_zero;
        const BddNodeV b = (i < rhs.size()) ? rhs[i] : BddNodeV::_zero;

        const BddNodeV axorb = a ^ b;
        sum.push_back(axorb ^ carry);
        carry = (a & b) | (carry & axorb);
    }
    sum.push_back(carry);
    return sum;
}

BddVec
multiplyWords(const BddVec& lhs, const BddVec& rhs) {
    BddVec acc(1, BddNodeV::_zero);
    for (size_t i = 0; i < rhs.size(); ++i) {
        BddVec partial(i, BddNodeV::_zero);
        partial.reserve(i + lhs.size());
        for (const BddNodeV& bit : lhs)
            partial.push_back(bit & rhs[i]);
        acc = addWords(acc, partial);
    }
    return acc;
}

BddVec
buildLinearVars(int n, int maxSupports) {
    BddVec vars;
    vars.reserve(n);
    for (int i = 0; i < n; ++i)
        vars.push_back(bddMgrV->getSupport(static_cast<size_t>(maxSupports - i)));
    return vars;
}

BddNodeV
buildParity(const BddVec& vars) {
    BddNodeV parity = BddNodeV::_zero;
    for (const BddNodeV& var : vars)
        parity ^= var;
    return parity;
}

BddNodeV
buildRandomLogic(const BddVec& vars, int n, uint32_t seed) {
    std::mt19937 rng(seed);
    std::uniform_int_distribution<int> modeDist(0, 2);
    std::uniform_int_distribution<int> idxDist(0, n - 1);

    const int terms = 3 * n;
    BddNodeV func   = BddNodeV::_zero;
    for (int t = 0; t < terms; ++t) {
        BddNodeV cube = BddNodeV::_one;
        bool hasLit   = false;
        for (int i = 0; i < n; ++i) {
            const int mode = modeDist(rng);  // 0 = don't care, 1 = pos, 2 = neg
            if (mode == 1) {
                cube &= vars[i];
                hasLit = true;
            } else if (mode == 2) {
                cube &= ~vars[i];
                hasLit = true;
            }
        }
        if (!hasLit) {
            const int idx = idxDist(rng);
            cube &= (modeDist(rng) == 2) ? ~vars[idx] : vars[idx];
        }
        func |= cube;
    }
    return func;
}

size_t
measureAdder(int n, const ExperimentConfig& cfg, int maxSupports) {
    return runExperiment([&]() {
        const AdderVars vars = buildInterleavedAdderVars(n, maxSupports);
        BddVec outputs       = addWords(vars.a, vars.b);  // sum[0..n-1], carry out
        if (cfg.dumpDot) {
            std::ofstream ofs(cfg.dotDir + "/adder_cout_n" + std::to_string(n) + ".dot");
            outputs.back().drawBdd("adder_cout_n" + std::to_string(n), ofs);
        }
        return countNodes(outputs);
    });
}

size_t
measureMultiplier(int n, const ExperimentConfig& cfg, int maxSupports) {
    return runExperiment([&]() {
        const AdderVars vars = buildInterleavedAdderVars(n, maxSupports);
        BddVec outputs       = multiplyWords(vars.a, vars.b);  // product bits
        outputs.resize(static_cast<size_t>(2 * n), BddNodeV::_zero);
        if (cfg.dumpDot) {
            std::ofstream ofs(cfg.dotDir + "/mult_msb_n" + std::to_string(n) + ".dot");
            outputs.back().drawBdd("mult_msb_n" + std::to_string(n), ofs);
        }
        return countNodes(outputs);
    });
}

size_t
measureCounterRelation(int n, const ExperimentConfig& cfg, int maxSupports) {
    return runExperiment([&]() {
        AdderVars vars = buildInterleavedAdderVars(n, maxSupports);
        BddNodeV rel   = BddNodeV::_one;
        BddNodeV carry = BddNodeV::_one;  // +1
        for (int i = 0; i < n; ++i) {
            const BddNodeV expectedNext = vars.a[i] ^ carry;
            rel &= ~(vars.b[i] ^ expectedNext);  // XNOR
            carry &= vars.a[i];
        }
        if (cfg.dumpDot) {
            std::ofstream ofs(cfg.dotDir + "/counter_rel_n" + std::to_string(n) + ".dot");
            rel.drawBdd("counter_rel_n" + std::to_string(n), ofs);
        }
        return countNodes({rel});
    });
}

size_t
measureParity(int n, const ExperimentConfig& cfg, int maxSupports) {
    return runExperiment([&]() {
        const BddVec vars = buildLinearVars(n, maxSupports);
        const BddNodeV p  = buildParity(vars);
        if (cfg.dumpDot) {
            std::ofstream ofs(cfg.dotDir + "/parity_n" + std::to_string(n) + ".dot");
            p.drawBdd("parity_n" + std::to_string(n), ofs);
        }
        return countNodes({p});
    });
}

size_t
measureRandomLogic(int n, const ExperimentConfig& cfg, int maxSupports) {
    return runExperiment([&]() {
        const BddVec vars = buildLinearVars(n, maxSupports);
        const BddNodeV r  = buildRandomLogic(vars, n, 0xC0FFEEu + static_cast<uint32_t>(n));
        if (cfg.dumpDot) {
            std::ofstream ofs(cfg.dotDir + "/random_logic_n" + std::to_string(n) + ".dot");
            r.drawBdd("random_logic_n" + std::to_string(n), ofs);
        }
        return countNodes({r});
    });
}

void
printSeries(const std::string& title, const std::vector<std::pair<int, size_t>>& points) {
    std::cout << "\n" << title << "\n";
    std::cout << "n,node_count\n";
    for (const auto& p : points)
        std::cout << p.first << "," << p.second << "\n";
}

ExperimentConfig
parseArgs(int argc, char** argv) {
    ExperimentConfig cfg;
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--dump-dot" && i + 1 < argc) {
            cfg.dumpDot = true;
            cfg.dotDir  = argv[++i];
        }
    }
    return cfg;
}

}  // namespace

int
main(int argc, char** argv) {
    const ExperimentConfig cfg = parseArgs(argc, argv);
    const int maxSupports      = 256;
    bddMgrV                    = new BddMgrV(static_cast<size_t>(maxSupports), 50021, 200003);

    std::vector<std::pair<int, size_t>> adder;
    std::vector<std::pair<int, size_t>> multiplier;
    std::vector<std::pair<int, size_t>> counter;
    std::vector<std::pair<int, size_t>> parity;
    std::vector<std::pair<int, size_t>> randomLogic;

    for (int n = 2; n <= 24; n += 2)
        adder.emplace_back(n, measureAdder(n, cfg, maxSupports));

    for (int n = 2; n <= 7; ++n)
        multiplier.emplace_back(n, measureMultiplier(n, cfg, maxSupports));

    for (int n = 2; n <= 24; n += 2)
        counter.emplace_back(n, measureCounterRelation(n, cfg, maxSupports));

    for (int n = 4; n <= 64; n += 4)
        parity.emplace_back(n, measureParity(n, cfg, maxSupports));

    for (int n = 4; n <= 24; n += 2)
        randomLogic.emplace_back(n, measureRandomLogic(n, cfg, maxSupports));

    std::cout << "BDD node-growth experiment (ROBDD)\n";
    std::cout << "variable order: interleaved LSB-first for arithmetic/counter; linear for parity/random\n";
    if (cfg.dumpDot)
        std::cout << "dot output dir: " << cfg.dotDir << "\n";

    printSeries("Adder (n-bit ripple, outputs = n sum bits + carry)", adder);
    printSeries("Multiplier (n x n ripple-array style, outputs = 2n bits)", multiplier);
    printSeries("Counter transition relation (next = state + 1 mod 2^n)", counter);
    printSeries("Parity (xor of n inputs)", parity);
    printSeries("Random SOP logic (3n random cubes)", randomLogic);

    return 0;
}

