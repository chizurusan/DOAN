// MSVC compatibility stubs for Firebase C++ SDK on older toolsets (pre-17.8).
// These provide the two missing CRT/STL internal symbols so the linker succeeds.

extern "C" {

// AVX2 wcsstr enable flag used by wmemcmp path in firebase_firestore.lib.
// Setting to 0 forces the scalar (non-AVX2) code path.
int _Avx2WmemEnabled = 0;

// Scalar fallback for MSVC STL's vectorised find_first_of helper.
// Signature matches the symbol the linker expects (unsigned __int64 == size_t on x64).
unsigned __int64 __std_find_first_of_trivial_pos_1(
    const char* const  haystack,
    unsigned __int64   haystackLen,
    const char* const  needle,
    unsigned __int64   needleLen)
{
    for (unsigned __int64 i = 0; i < haystackLen; ++i) {
        for (unsigned __int64 j = 0; j < needleLen; ++j) {
            if (haystack[i] == needle[j]) {
                return i;
            }
        }
    }
    return haystackLen;
}

} // extern "C"
