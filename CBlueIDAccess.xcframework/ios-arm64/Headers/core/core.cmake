#
# Setup log level depending on build mode
#
if(CMAKE_BUILD_TYPE MATCHES "Debug")
    set(BLUE_LOG_LEVEL 4)
else()
    set(BLUE_LOG_LEVEL 1)
endif()

add_definitions(-DBLUE_LOG_LEVEL=${BLUE_LOG_LEVEL})

#
# Setup build time in utc
#
string(TIMESTAMP BUILD_TIME "%s" UTC)
add_definitions(-DBLUE_BUILD_TIME=${BUILD_TIME})

# Include external libraries
include(${CMAKE_CURRENT_LIST_DIR}/../ext/ext.cmake)

#
# Setup core sources
#
file(GLOB_RECURSE CORE_SOURCES ${CMAKE_CURRENT_LIST_DIR}/*.c)

#
# Add libraries
#
set(CORE_SOURCES ${CORE_SOURCES} ${WOLF_CRYPT_SOURCES} ${NANOPB_SOURCES})

#
# Add BlueCore proto file
#
set(PROTO_SOURCES ${CMAKE_CURRENT_LIST_DIR}/../proto/nanopb/BlueCore.pb.c)
set(CORE_SOURCES ${CORE_SOURCES} ${PROTO_SOURCES})
include_directories(${CMAKE_CURRENT_LIST_DIR}/../proto/nanopb)

#
# Setup SDK files which are different as ie wolfcrypt is not part of the headers
#
set(CORE_SDK_SOURCES ${CORE_SOURCES})

#
# Read the VERSION file which includes our version number and makes it available everywhere
#
file(STRINGS "${CMAKE_CURRENT_LIST_DIR}/../../VERSION" BLUE_VERSION)
if (BLUE_VERSION LESS 1 OR BLUE_VERSION GREATER 10000)
message(FATAL_ERROR "Invalid or missing BLUE_VERSION: ${BLUE_VERSION}")
endif()

add_definitions(-DBLUE_VERSION=${BLUE_VERSION})

#
# Echo some infos on the build
#
MESSAGE(STATUS "Building blue core with CMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}, BLUE_LOG_LEVEL=${BLUE_LOG_LEVEL}, BLUE_VERSION=${BLUE_VERSION}")