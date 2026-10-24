# For more information about using CMake with Flutter:
# https://flutter.dev/to/cpp-projects

cmake_minimum_required(VERSION 3.22.1)

project("ai_chat_native" CXX)

add_library(
    ai_chat_native
    SHARED
    native-lib.cpp
)

set_target_properties(ai_chat_native PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
)

find_library(log-lib log)

target_link_libraries(
    ai_chat_native
    ${log-lib}
)
