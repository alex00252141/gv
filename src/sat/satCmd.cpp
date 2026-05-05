#ifndef GV_SIM_CMD_C
#define GV_SIM_CMD_C

#include "satCmd.h"

#include <iomanip>
#include <fstream>

#include "gvMsg.h"

#include "minisatMgr.h"
#include "satMgr.h"
#include "util.h"

#include "iostream"

bool initSatCmd() {
    return (gvCmdMgr->regCmd("SATSolve DIMACS", 4, 6, new SatSolveDimacCmd));
}

using namespace gv::sat;

//----------------------------------------------------------------------
// EXPeriment
//----------------------------------------------------------------------
GVCmdExecStatus SatSolveDimacCmd::exec(const string& option) {
    //! Place your experimental functions and commands here
    vector<string> options;
    GVCmdExec::lexOptions(option, options);

    if (options.empty()) return GVCmdExec::errorOption(GV_CMD_OPT_MISSING, "-File");

    string filename;
    int  conflictLimit = -1;
    bool fileSet       = false;
    bool limitSet      = false;

    for (size_t i = 0; i < options.size(); ++i) {
        const string& token = options[i];
        if (checkOptionToken(token, "-File", 2)) {
            if (fileSet) return GVCmdExec::errorOption(GV_CMD_OPT_EXTRA, token);
            if (++i >= options.size()) return GVCmdExec::errorOption(GV_CMD_OPT_MISSING, token);
            filename = options[i];
            fileSet  = true;
            continue;
        }
        if (checkOptionToken(token, "-ConflictMax", 2)) {
            if (limitSet) return GVCmdExec::errorOption(GV_CMD_OPT_EXTRA, token);
            if (++i >= options.size()) return GVCmdExec::errorOption(GV_CMD_OPT_MISSING, token);
            if (!myStr2Int(options[i], conflictLimit) || conflictLimit < 0)
                return GVCmdExec::errorOption(GV_CMD_OPT_ILLEGAL, options[i]);
            limitSet = true;
            continue;
        }
        return GVCmdExec::errorOption(GV_CMD_OPT_ILLEGAL, token);
    }

    if (!fileSet) return GVCmdExec::errorOption(GV_CMD_OPT_MISSING, "-File");

    ifstream file(filename);
    if (!file.is_open()) {
        gvMsg(GV_MSG_ERR) << "File " << filename << " does NOT Exist !!" << endl;
        return GVCmdExec::errorOption(GV_CMD_OPT_ILLEGAL, filename);
    }
    file.close();

    MinisatMgr gvSatSolver;
    gvSatSolver.solve_dimacs_cnf(filename, conflictLimit);

    return GV_CMD_EXEC_DONE;
}

void SatSolveDimacCmd::usage(const bool& verbose) const {
    gvMsg(GV_MSG_IFO) << "Usage: SATSolve DIMACS <-File <string(dimacsFormatFileName)> > "
                      << "[-ConflictMax <non-negative integer>]" << endl;
}

void SatSolveDimacCmd::help() const {
    gvMsg(GV_MSG_IFO) << setw(20) << std::left << "SATSolve DIMACS: "
                      << "Command for satsolving DIMACS format file." << endl;
}

#endif
