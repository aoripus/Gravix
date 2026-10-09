#include "../Sources/RDPBridge/TransferSafety.hpp"
#include <cassert>
#include <iostream>
int main() {
    using gravix::safeRelativePath;
    assert(safeRelativePath("report.pdf"));
    assert(safeRelativePath("资料\\项目\\进度.xlsx"));
    for (auto path : {"", "../escape", "dir/../escape", "/etc/passwd", "\\\\host\\share", "C:\\file", "a//b", "a\\.\\b", "a:b", "a/.. ", "dir./file"}) assert(!safeRelativePath(path));
    assert(!safeRelativePath(std::string("bad\0file", 8)));
    assert(gravix::validRange(100, 90, 10));
    assert(!gravix::validRange(100, 90, 11));
    assert(!gravix::validRange(100, UINT64_MAX, 1));
    assert(!gravix::validRange(UINT64_MAX, 0, 2 * 1024 * 1024));
    std::cout << "Transfer safety tests passed\n";
}
