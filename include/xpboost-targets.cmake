# see BoostConfig.cmake for details on the following variables
set(Boost_FIND_QUIETLY TRUE)
set(Boost_USE_STATIC_LIBS ON)
set(Boost_USE_MULTITHREADED ON)
set(Boost_USE_STATIC_RUNTIME ON)
#set(Boost_VERBOSE TRUE) # enable verbose output of BoostConfig.cmake
#set(Boost_DEBUG TRUE) # enable debug (even more verbose) output of BoostConfig.cmake
set(_boost_cmake_dir ${CMAKE_CURRENT_LIST_DIR}/Boost-@CMAKE_PROJECT_VERSION@)
# Set version variables BoostConfig.cmake normally gets from BoostConfigVersion.cmake
set(Boost_VERSION @CMAKE_PROJECT_VERSION@)
if(Boost_VERSION MATCHES "^([0-9]+)\\.([0-9]+)\\.([0-9]+)$")
  set(Boost_VERSION_MAJOR ${CMAKE_MATCH_1})
  set(Boost_VERSION_MINOR ${CMAKE_MATCH_2})
  set(Boost_VERSION_PATCH ${CMAKE_MATCH_3})
endif()
# First "trick" include: run BoostConfig.cmake with no requested components.
# This creates Boost::headers / Boost::boost (guarded), and it defines the
# internal __boost_hdronly_libraries list for us.
set(Boost_FIND_COMPONENTS "")
include(${_boost_cmake_dir}/BoostConfig.cmake)
set(_boost_hdronly ${__boost_hdronly_libraries})
# Discover compiled component package directories next to Boost-<version>.
file(GLOB _boost_comp_dirs LIST_DIRECTORIES TRUE
  "${_boost_cmake_dir}/../boost_*-@CMAKE_PROJECT_VERSION@"
  )
set(_boost_comps)
foreach(_dir IN LISTS _boost_comp_dirs)
  get_filename_component(_name "${_dir}" NAME)
  if(_name MATCHES "^boost_([a-z0-9_]+)-@CMAKE_PROJECT_VERSION@$")
    list(APPEND _boost_comps "${CMAKE_MATCH_1}")
  endif()
endforeach()
list(REMOVE_ITEM _boost_comps "headers")  # always handled by BoostConfig.cmake
# Request every available compiled and header-only component, but as optional
# so one missing component does not fail the whole find_package call.
find_package(Boost @CMAKE_PROJECT_VERSION@ BYPASS_PROVIDER REQUIRED
  OPTIONAL_COMPONENTS ${_boost_comps} ${_boost_hdronly}
  PATHS ${_boost_cmake_dir} NO_DEFAULT_PATH
  )
mark_as_advanced(Boost_DIR)
if(UNIX)
  include(CheckLibraryExists)
  function(checkLibraryConcat lib symbol liblist)
    string(TOUPPER ${lib} LIB)
    check_library_exists("${lib}" "${symbol}" "" XP_BOOST_HAS_${LIB})
    if(XP_BOOST_HAS_${LIB})
      list(APPEND ${liblist} ${lib})
      set(${liblist} ${${liblist}} PARENT_SCOPE)
    endif()
  endfunction()
  checkLibraryConcat(rt shm_open headersDeps) # req'd by interprocess
  if(DEFINED headersDeps AND TARGET Boost::headers)
    get_target_property(libs Boost::headers INTERFACE_LINK_LIBRARIES)
    if(libs)
      list(APPEND libs ${headersDeps})
    else()
      set(libs ${headersDeps})
    endif()
    set_target_properties(Boost::headers PROPERTIES INTERFACE_LINK_LIBRARIES "${libs}")
  endif()
endif()
