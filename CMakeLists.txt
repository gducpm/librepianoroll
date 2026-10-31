cmake_minimum_required(VERSION 3.16)
project(godot_fluidsynth LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Output directory
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/addons/fluidsynth/bin")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/addons/fluidsynth/bin")

# Extension target
add_library(godot_fluidsynth SHARED
    src/fluidsynth_bridge/fluidsynth_bridge.cpp
)

target_include_directories(godot_fluidsynth PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
)

# FluidSynth discovery / linking per platform
if(WIN32)
    set_target_properties(godot_fluidsynth PROPERTIES
        PREFIX ""
        OUTPUT_NAME "godot_fluidsynth"
    )
    # If custom FluidSynth path is provided, use it
    if(DEFINED FLUIDSYNTH_DIR)
        target_include_directories(godot_fluidsynth PRIVATE "${FLUIDSYNTH_DIR}/include")
        target_link_directories(godot_fluidsynth PRIVATE "${FLUIDSYNTH_DIR}/lib")
        target_link_libraries(godot_fluidsynth PRIVATE libfluidsynth-3)
    else()
        # Default vendored build path
        file(GLOB FS_DIRS "${CMAKE_CURRENT_SOURCE_DIR}/build/fluidsynth/fluidsynth-*")
        if(FS_DIRS)
            list(GET FS_DIRS 0 FS_DIR)
            target_include_directories(godot_fluidsynth PRIVATE "${FS_DIR}/include")
            target_link_directories(godot_fluidsynth PRIVATE "${FS_DIR}/lib")
            target_link_libraries(godot_fluidsynth PRIVATE libfluidsynth-3)
        else()
            find_package(PkgConfig REQUIRED)
            pkg_check_modules(FLUIDSYNTH REQUIRED fluidsynth)
            target_include_directories(godot_fluidsynth PRIVATE ${FLUIDSYNTH_INCLUDE_DIRS})
            target_link_libraries(godot_fluidsynth PRIVATE ${FLUIDSYNTH_LIBRARIES})
        endif()
    endif()
elseif(APPLE)
    set_target_properties(godot_fluidsynth PROPERTIES
        PREFIX "lib"
        OUTPUT_NAME "godot_fluidsynth"
        INSTALL_RPATH "@loader_path"
        BUILD_WITH_INSTALL_RPATH TRUE
    )
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(FLUIDSYNTH REQUIRED fluidsynth)
    target_include_directories(godot_fluidsynth PRIVATE ${FLUIDSYNTH_INCLUDE_DIRS})
    target_link_libraries(godot_fluidsynth PRIVATE ${FLUIDSYNTH_LIBRARIES})
else()
    # GNU+Linux
    set_target_properties(godot_fluidsynth PROPERTIES
        PREFIX "lib"
        OUTPUT_NAME "godot_fluidsynth"
        INSTALL_RPATH "$ORIGIN"
        BUILD_WITH_INSTALL_RPATH TRUE
    )
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(FLUIDSYNTH REQUIRED fluidsynth)
    target_include_directories(godot_fluidsynth PRIVATE ${FLUIDSYNTH_INCLUDE_DIRS})
    target_link_libraries(godot_fluidsynth PRIVATE ${FLUIDSYNTH_LIBRARIES})
endif()
