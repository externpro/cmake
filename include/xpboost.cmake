function(getBootstrapCmd _bootstrapCmd)
  if(MSVC)
    set(bsCmd ${CMAKE_SOURCE_DIR}/bootstrap.bat)
    if(DEFINED MSVC_TOOLSET_VERSION)
      list(APPEND bsCmd vc${MSVC_TOOLSET_VERSION})
    endif()
  else()
    set(bsCmd ${CMAKE_SOURCE_DIR}/bootstrap.sh)
    if(CMAKE_COMPILER_IS_GNUCXX)
      list(APPEND bsCmd --with-toolset=gcc)
    elseif("${CMAKE_CXX_COMPILER_ID}" MATCHES "Clang") # LLVM/Apple Clang
      list(APPEND bsCmd --with-toolset=clang)
    else()
      message(FATAL_ERROR "xpboost.cmake: compiler support lacking: ${CMAKE_CXX_COMPILER_ID}")
    endif()
  endif()
  set(${_bootstrapCmd} ${bsCmd} PARENT_SCOPE)
endfunction()
########################################
function(userConfigJam _jamFile)
  set(cfgFile ${CMAKE_BINARY_DIR}/user-config.jam)
  xpFindPkg(PKGS ZLIB BZip2)
  if(TARGET ZLIB::ZLIB)
    get_target_property(loc ZLIB::ZLIB IMPORTED_LOCATION_RELEASE)
    get_filename_component(libDir ${loc} DIRECTORY)
    get_filename_component(libName ${loc} NAME)
    string(REPLACE "${CMAKE_STATIC_LIBRARY_PREFIX}" "" libName ${libName})
    string(REPLACE "${CMAKE_STATIC_LIBRARY_SUFFIX}" "" libName ${libName})
    get_target_property(incDir ZLIB::ZLIB INTERFACE_INCLUDE_DIRECTORIES)
    list(FILTER incDir INCLUDE REGEX "zlib$") # include directory that ends with zlib
    string(REPLACE "xpv" "" cleanZlibVer "${ZLIB_VER}")
    string(REPLACE "v" "" cleanZlibVer "${cleanZlibVer}")
    set(cfgContents "using zlib : ${cleanZlibVer} : <search>${libDir} <name>${libName} <include>${incDir} ;\n")
  endif()
  if(TARGET BZip2::BZip2)
    get_target_property(loc BZip2::BZip2 IMPORTED_LOCATION_RELEASE)
    get_filename_component(libDir ${loc} DIRECTORY)
    get_filename_component(libName ${loc} NAME)
    string(REPLACE "${CMAKE_STATIC_LIBRARY_PREFIX}" "" libName ${libName})
    string(REPLACE "${CMAKE_STATIC_LIBRARY_SUFFIX}" "" libName ${libName})
    get_target_property(incDir BZip2::BZip2 INTERFACE_INCLUDE_DIRECTORIES)
    string(REPLACE "xpv" "" cleanBzip2Ver "${BZIP2_VER}")
    string(REPLACE "v" "" cleanBzip2Ver "${cleanBzip2Ver}")
    set(cfgContents "${cfgContents}using bzip2 : ${cleanBzip2Ver} : <search>${libDir} <name>${libName} <include>${incDir}/bzip2 ;\n")
  endif()
  file(WRITE ${cfgFile} "${cfgContents}")
  # Boost.Python build
  find_package(Python "3.6...<3.13" COMPONENTS Interpreter Development)
  if(Python_Interpreter_FOUND AND Python_Development_FOUND)
    if(XP_BUILD_VERBOSE)
      message(STATUS "Python_EXECUTABLE: ${Python_EXECUTABLE}")
      message(STATUS "Python_VERSION: ${Python_VERSION}")
      message(STATUS "Python_INCLUDE_DIRS: ${Python_INCLUDE_DIRS}")
      message(STATUS "Python_LIBRARIES: ${Python_LIBRARIES}")
    endif()
    get_filename_component(Python_LIB_DIR ${Python_LIBRARIES} DIRECTORY)
    file(APPEND ${cfgFile}
      "using python\n"
      "  : ${Python_VERSION_MAJOR}.${Python_VERSION_MINOR}\n"
      "  : \"${Python_EXECUTABLE}\"\n"
      "  : \"${Python_INCLUDE_DIRS}\"\n"
      "  : \"${Python_LIB_DIR}\"\n"
      "  : <python-debugging>off ;"
      )
  else()
    message(FATAL_ERROR "xpboost.cmake: unable to build boost.python, required Python not found")
  endif()
  set(${_jamFile} "${cfgFile}" PARENT_SCOPE)
endfunction()
########################################
function(stringToList stringlist lvalue)
  if(NOT "${stringlist}" STREQUAL "")
    string(STRIP ${stringlist} stringlist) # remove leading and trailing spaces
    string(REPLACE " -" ";-" listlist ${stringlist})
    foreach(item ${listlist})
      list(APPEND templist ${lvalue}="${item}")
    endforeach()
    set(${lvalue} "${templist}" PARENT_SCOPE)
  endif()
endfunction()
########################################
function(getB2Args _b2Args)
  if(MSVC)
    if(DEFINED MSVC_TOOLSET_VERSION)
      math(EXPR major ${MSVC_TOOLSET_VERSION}/10)
      math(EXPR minor ${MSVC_TOOLSET_VERSION}%10)
      set(b2toolset msvc-${major}.${minor})
    else()
      message(FATAL_ERROR "xpboost.cmake: MSVC toolset version unknown")
    endif()
  else()
    if(CMAKE_COMPILER_IS_GNUCXX)
      set(b2toolset gcc)
    elseif("${CMAKE_CXX_COMPILER_ID}" MATCHES "Clang") # LLVM/Apple Clang
      set(b2toolset clang)
    else()
      message(FATAL_ERROR "xpboost.cmake: compiler support lacking: ${CMAKE_CXX_COMPILER_ID}")
    endif()
    # xpflags populates CMAKE_*_FLAGS
    stringToList("${CMAKE_CXX_FLAGS}" cxxflags)
    stringToList("${CMAKE_C_FLAGS}" cflags)
    stringToList("${CMAKE_EXE_LINKER_FLAGS}" linkflags)
    set(b2flags "${cxxflags}" "${cflags}" "${linkflags}")
  endif()
  userConfigJam(userConfigJamFile)
  if(CMAKE_SIZEOF_VOID_P EQUAL 8)
    set(b2platform 64)
  elseif(CMAKE_SIZEOF_VOID_P EQUAL 4)
    set(b2platform 32)
  endif()
  set(b2variant "debug,release")
  set(b2runtimeLink "static")
  set(b2Args --ignore-site-config --layout=versioned --user-config=${userConfigJamFile}
    link=static threading=multi address-model=${b2platform} variant=${b2variant}
    runtime-link=${b2runtimeLink} toolset=${b2toolset} ${b2flags} --debug-configuration
    )
  # libraries with build issues
  set(excludeLibs locale math mpi)
  # libraries excluded until there's an argument to use them
  list(APPEND excludeLibs context contract coroutine fiber graph_parallel stacktrace type_erasure wave)
  foreach(lib ${excludeLibs})
    list(APPEND b2Args --without-${lib})
  endforeach()
  set(${_b2Args} "${b2Args}" PARENT_SCOPE)
endfunction()
########################################
include(ExternalProject)
set_property(DIRECTORY PROPERTY EP_BASE ${CMAKE_BINARY_DIR}/epbase)
get_property(baseDir DIRECTORY PROPERTY "EP_BASE")
getBootstrapCmd(bootstrapCmd)
getB2Args(b2Args)
set(tgt b2.build)
set(b2Cmd ${CMAKE_SOURCE_DIR}/b2${CMAKE_EXECUTABLE_SUFFIX} ${b2Args})
set(b2Stage stage --stagedir=${baseDir}/Build/${tgt}/stage)
set(CMAKE_INSTALL_CMAKEDIR ${CMAKE_INSTALL_DATADIR}/cmake)
set(b2Install install
  --libdir=<INSTALL_DIR>/${CMAKE_INSTALL_LIBDIR}
  --includedir=<INSTALL_DIR>/${CMAKE_INSTALL_INCLUDEDIR}
  --cmakedir=<INSTALL_DIR>/${CMAKE_INSTALL_CMAKEDIR}
  --datarootdir=<INSTALL_DIR>/${CMAKE_INSTALL_DATAROOTDIR}
  )
ExternalProject_Add(${tgt}
  SOURCE_DIR ${CMAKE_SOURCE_DIR}
  DOWNLOAD_COMMAND ""
  CONFIGURE_COMMAND ${bootstrapCmd}
  BUILD_COMMAND ${b2Cmd} ${b2Stage} BUILD_IN_SOURCE 1
  INSTALL_COMMAND ${b2Cmd} ${b2Install}
  )
if(XP_BUILD_VERBOSE)
  message(STATUS "target: ${tgt}")
  xpVerboseListing("[bootstrap]" "${bootstrapCmd}")
  xpVerboseListing("[b2]" "${b2Cmd}")
  xpVerboseListing("[stage]" "${b2Stage}")
  xpVerboseListing("[install]" "${b2Install}")
endif()
configure_file(${CMAKE_CURRENT_LIST_DIR}/xpboost-targets.cmake
  ${baseDir}/Install/${tgt}/${CMAKE_INSTALL_CMAKEDIR}/xpboost-targets.cmake @ONLY
  )
xpExternPackage(REPO_NAME boost TARGETS_FILE xpboost-targets NO_EXPORT
  BASE boost-${CMAKE_PROJECT_VERSION} XPDIFF "native" DEPS bzip2 zlib
  WEB "http://www.boost.org/ 'Boost website'" UPSTREAM "github.com/boostorg/boost"
  DESC "libraries that give C++ a boost"
  LICENSE "[BSL-1.0](http://www.boost.org/users/license.html 'Boost Software License')"
  )
install(DIRECTORY ${baseDir}/Install/${tgt}/ DESTINATION . USE_SOURCE_PERMISSIONS)
