#pragma once
#include <string>
#include <vector>
#include <algorithm>

namespace gravix {
// Windows clipboard names are relative paths, never filesystem authority.
inline bool safeRelativePath(const std::string& input) {
    if (input.empty() || input.size() > 1024 || input.front() == '/' || input.front() == '\\') return false;
    std::string part;
    for (unsigned char c : input) {
        if (c < 32 || c == ':' || c == 127) return false;
        if (c == '/' || c == '\\') {
            if (part.empty() || part == "." || part == ".." || part.back() == ' ' || part.back() == '.') return false;
            part.clear();
        } else part += c;
    }
    return !part.empty() && part != "." && part != ".." && part.back() != ' ' && part.back() != '.';
}
inline bool validRange(uint64_t size, uint64_t offset, uint32_t count) {
    return count <= 1024 * 1024 && offset <= size && count <= size - offset;
}
}
