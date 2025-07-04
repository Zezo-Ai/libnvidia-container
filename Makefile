# Copyright (c) 2017-2021, NVIDIA CORPORATION.  All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

.PHONY: all tools shared static deps install uninstall dist depsclean mostlyclean clean distclean
.DEFAULT_GOAL := all

##### Global variables #####

WITH_NVCGO   ?= yes
WITH_LIBELF  ?= no
WITH_TIRPC   ?= no
WITH_SECCOMP ?= yes

##### Global definitions #####

export prefix      = /usr/local
export exec_prefix = $(prefix)
export bindir      = $(exec_prefix)/bin
export libdir      = $(exec_prefix)/lib
export docdir      = $(prefix)/share/doc
export libdbgdir   = $(prefix)/lib/debug$(libdir)
export includedir  = $(prefix)/include
export pkgconfdir  = $(libdir)/pkgconfig

export PKG_DIR     ?= $(CURDIR)/pkg
export SRCS_DIR    ?= $(CURDIR)/src
export DEPS_DIR    ?= $(CURDIR)/deps
export DIST_DIR    ?= $(CURDIR)/dist
export MAKE_DIR    ?= $(CURDIR)/mk
export DEBUG_DIR   ?= $(CURDIR)/.debug

#export DISTRIB    ?=
#export SECTION    ?=

include $(MAKE_DIR)/common.mk
include $(MAKE_DIR)/docker.mk

##### File definitions #####

DOC_FILES    := $(CURDIR)/NOTICE \
                $(CURDIR)/LICENSE \
                $(CURDIR)/COPYING \
                $(CURDIR)/COPYING.LESSER

BUILD_DEFS   := $(SRCS_DIR)/build.h

LIB_INCS     := $(SRCS_DIR)/nvc.h
LIB_SRCS     := $(SRCS_DIR)/driver.c        \
                $(SRCS_DIR)/dxcore.c        \
                $(SRCS_DIR)/elftool.c       \
                $(SRCS_DIR)/error_generic.c \
                $(SRCS_DIR)/error.c         \
                $(SRCS_DIR)/ldcache.c       \
                $(SRCS_DIR)/nvc.c           \
                $(SRCS_DIR)/nvc_ldcache.c   \
                $(SRCS_DIR)/nvc_info.c      \
                $(SRCS_DIR)/nvc_mount.c     \
                $(SRCS_DIR)/nvc_container.c \
                $(SRCS_DIR)/options.c       \
                $(SRCS_DIR)/rpc.c           \
                $(SRCS_DIR)/utils.c

ifeq ($(WITH_NVCGO), yes)
LIB_SRCS += $(SRCS_DIR)/cgroup.c \
            $(SRCS_DIR)/nvcgo.c
else
LIB_SRCS += $(SRCS_DIR)/cgroup_legacy.c
endif

# Order sensitive (see flags definitions)
LIB_RPC_SPEC := $(SRCS_DIR)/nvc_rpc.x
LIB_RPC_SRCS := $(SRCS_DIR)/nvc_rpc.h \
                $(SRCS_DIR)/nvc_xdr.c \
                $(SRCS_DIR)/nvc_svc.c \
                $(SRCS_DIR)/nvc_clt.c

BIN_SRCS     := $(SRCS_DIR)/cli/common.c    \
                $(SRCS_DIR)/cli/compat_mode.c \
                $(SRCS_DIR)/cli/configure.c \
                $(SRCS_DIR)/cli/dsl.c       \
                $(SRCS_DIR)/cli/info.c      \
                $(SRCS_DIR)/cli/list.c      \
                $(SRCS_DIR)/cli/main.c      \
                $(SRCS_DIR)/cli/libnvc.c    \
                $(SRCS_DIR)/error_generic.c \
                $(SRCS_DIR)/utils.c

LIB_SCRIPT   = $(SRCS_DIR)/$(LIB_NAME).lds
BIN_SCRIPT   = $(SRCS_DIR)/cli/$(BIN_NAME).lds

##### Target definitions #####

ARCH    ?= $(call getarch)

ifeq ($(VERSION_MAJOR),)
$(error Invalid major version)
endif
ifeq ($(VERSION_MINOR),)
$(error Invalid minor version)
endif
ifeq ($(VERSION_PATCH),)
$(error Invalid patch version)
endif

$(SRCS_DIR)/nvc.h: $(SRCS_DIR)/nvc.h.template
	cat $< | \
	sed -e 's/{{NVC_MAJOR}}/$(VERSION_MAJOR)/g' | \
	sed -e 's/{{NVC_MINOR}}/$(VERSION_MINOR)/g' | \
	sed -e 's/{{NVC_PATCH}}/$(VERSION_PATCH)/g' | \
	sed -e 's/{{NVC_TAG}}/$(if $(TAG),"$(TAG)",)/g' | \
	sed -e 's/{{NVC_VERSION}}/"$(VERSION_STRING)"/g' > $@

BIN_NAME    := nvidia-container-cli
LIB_NAME    := libnvidia-container
LIB_STATIC  := $(LIB_NAME).a
LIB_SHARED  := $(LIB_NAME).so.$(VERSION)
LIB_SONAME  := $(LIB_NAME).so.$(VERSION_MAJOR)
LIB_SYMLINK := $(LIB_NAME).so
LIB_PKGCFG  := $(LIB_NAME).pc

LIBGO_NAME    := $(LIB_NAME)-go
LIBGO_SHARED  := $(LIBGO_NAME).so.$(VERSION)
LIBGO_SONAME  := $(LIBGO_NAME).so.$(VERSION_MAJOR)
LIBGO_SYMLINK := $(LIBGO_NAME).so

##### Flags definitions #####

# Common flags
CPPFLAGS := -D_GNU_SOURCE -D_FORTIFY_SOURCE=2 $(CPPFLAGS)
CFLAGS   := -std=gnu11 -O2 -g -fdata-sections -ffunction-sections -fplan9-extensions -fstack-protector -fno-strict-aliasing -fvisibility=hidden \
            -Wall -Wextra -Wcast-align -Wpointer-arith -Wmissing-prototypes -Wnonnull \
            -Wwrite-strings -Wlogical-op -Wformat=2 -Wmissing-format-attribute -Winit-self -Wshadow \
            -Wstrict-prototypes -Wunreachable-code -Wconversion -Wsign-conversion \
            -Wno-unknown-warning-option -Wno-format-extra-args -Wno-gnu-alignof-expression $(CFLAGS)
LDFLAGS  := -Wl,-zrelro -Wl,-znow -Wl,-zdefs -Wl,--gc-sections $(LDFLAGS)
LDLIBS   := $(LDLIBS)

# Library flags (recursively expanded to handle target-specific flags)
LIB_CPPFLAGS       = -DNV_LINUX -isystem $(DEPS_DIR)$(includedir) -include $(BUILD_DEFS)
LIB_CFLAGS         = -fPIC
LIB_LDFLAGS        = -L$(DEPS_DIR)$(libdir) -shared -Wl,-soname=$(LIB_SONAME)
LIB_LDLIBS_STATIC  = -l:libnvidia-modprobe-utils.a
LIB_LDLIBS_SHARED  = -ldl -lcap
ifeq ($(WITH_NVCGO), yes)
LIB_CPPFLAGS       += -DWITH_NVCGO
LIB_LDLIBS_SHARED  += -lpthread
endif
ifeq ($(WITH_LIBELF), yes)
LIB_CPPFLAGS       += -DWITH_LIBELF
LIB_LDLIBS_SHARED  += -lelf
else
LIB_LDLIBS_STATIC  += -l:libelf.a
endif
ifeq ($(WITH_TIRPC), yes)
LIB_CPPFLAGS       += -isystem $(DEPS_DIR)$(includedir)/tirpc -DWITH_TIRPC
LIB_LDLIBS_STATIC  += -l:libtirpc.a
LIB_LDLIBS_SHARED  += -lpthread
endif
ifeq ($(WITH_SECCOMP), yes)
LIB_CPPFLAGS       += -DWITH_SECCOMP $(shell pkg-config --cflags libseccomp)
LIB_LDLIBS_SHARED  += $(shell pkg-config --libs libseccomp)
endif
LIB_CPPFLAGS       += $(CPPFLAGS)
LIB_CFLAGS         += $(CFLAGS)
LIB_LDFLAGS        += $(LDFLAGS)
LIB_LDLIBS_STATIC  +=
LIB_LDLIBS_SHARED  += $(LDLIBS)
LIB_LDLIBS         = $(LIB_LDLIBS_STATIC) $(LIB_LDLIBS_SHARED)

# Binary flags (recursively expanded to handle target-specific flags)
BIN_CPPFLAGS       = -include $(BUILD_DEFS) $(CPPFLAGS)
BIN_CFLAGS         = -I$(SRCS_DIR) -fPIE -flto $(CFLAGS)
BIN_LDFLAGS        = -L. -pie $(LDFLAGS) -Wl,-rpath='$$ORIGIN/../$$LIB'
BIN_LDLIBS         = -l:$(LIB_SHARED) -ldl -lcap $(LDLIBS)

$(word 1,$(LIB_RPC_SRCS)): RPCGENFLAGS=-h
$(word 2,$(LIB_RPC_SRCS)): RPCGENFLAGS=-c
$(word 3,$(LIB_RPC_SRCS)): RPCGENFLAGS=-m
$(word 4,$(LIB_RPC_SRCS)): RPCGENFLAGS=-l

ifeq ($(WITH_NVCGO), yes)
$(LIB_RPC_SRCS): RPCGENFLAGS+=-DWITH_NVCGO
endif

##### Private rules #####

BIN_OBJS       := $(BIN_SRCS:.c=.o)
LIB_OBJS       := $(LIB_SRCS:.c=.lo) $(patsubst %.c,%.lo,$(filter %.c,$(LIB_RPC_SRCS)))
LIB_STATIC_OBJ := $(SRCS_DIR)/$(LIB_STATIC:.a=.lo)
DEPENDENCIES   := $(BIN_OBJS:%.o=%.d) $(LIB_OBJS:%.lo=%.d)

$(BUILD_DEFS):
	@printf '#define BUILD_DATE     "%s"\n' '$(strip $(DATE))' >$(BUILD_DEFS)
	@printf '#define BUILD_COMPILER "%s " __VERSION__\n' '$(notdir $(COMPILER))' >>$(BUILD_DEFS)
	@printf '#define BUILD_FLAGS    "%s"\n' '$(strip $(CPPFLAGS) $(CFLAGS) $(LDFLAGS))' >>$(BUILD_DEFS)
	@printf '#define BUILD_REVISION "%s"\n' '$(strip $(REVISION))' >>$(BUILD_DEFS)
	@printf '#define BUILD_PLATFORM "%s"\n' '$(strip $(PLATFORM))' >>$(BUILD_DEFS)

$(LIB_RPC_SRCS): $(LIB_RPC_SPEC)
	$(RM) $@
	cd $(dir $@) && $(RPCGEN) $(RPCGENFLAGS) -C -M -N -o $(notdir $@) $(LIB_RPC_SPEC)

$(LIB_OBJS): %.lo: %.c | deps $(SRCS_DIR)/nvc.h
	$(CC) $(LIB_CFLAGS) $(LIB_CPPFLAGS) -MMD -MF $*.d -c $(OUTPUT_OPTION) $<

$(BIN_OBJS): %.o: %.c | shared
	$(CC) $(BIN_CFLAGS) $(BIN_CPPFLAGS) -MMD -MF $*.d -c $(OUTPUT_OPTION) $<

-include $(DEPENDENCIES)

$(LIB_SHARED): $(LIB_OBJS)
	$(MKDIR) -p $(DEBUG_DIR)
	$(CC) $(LIB_CFLAGS) $(LIB_CPPFLAGS) $(LIB_LDFLAGS) $(OUTPUT_OPTION) $^ $(LIB_SCRIPT) $(LIB_LDLIBS)
	$(OBJCPY) --only-keep-debug $@ $(LIB_SONAME)
	$(OBJCPY) --add-gnu-debuglink=$(LIB_SONAME) $@
	$(MV) $(LIB_SONAME) $(DEBUG_DIR)
	$(STRIP) --strip-unneeded -R .comment $@

$(LIB_STATIC_OBJ): $(LIB_OBJS)
	# FIXME Handle user-defined LDFLAGS and LDLIBS
	$(LD) -d -r --exclude-libs ALL -L$(DEPS_DIR)$(libdir) $(OUTPUT_OPTION) $^ $(LIB_LDLIBS_STATIC)
	$(OBJCPY) --localize-hidden $@
	$(STRIP) --strip-unneeded -R .comment $@

$(BIN_NAME): $(BIN_OBJS)
	$(CC) $(BIN_CFLAGS) $(BIN_CPPFLAGS) $(BIN_LDFLAGS) $(OUTPUT_OPTION) $^ $(BIN_SCRIPT) $(BIN_LDLIBS)
	$(STRIP) --strip-unneeded -R .comment $@

##### Public rules #####

all: CPPFLAGS += -DNDEBUG
all: shared static tools

# Run with ASAN_OPTIONS="protect_shadow_gap=0" to avoid CUDA OOM errors
debug: CFLAGS += -pedantic -fsanitize=undefined -fno-omit-frame-pointer -fno-common -fsanitize=address
debug: LDLIBS += -lubsan
debug: STRIP  := @echo skipping: strip
debug: shared static tools

tools: $(BIN_NAME)

shared: $(LIB_SHARED)

static: $(LIB_STATIC)($(LIB_STATIC_OBJ))

deps: $(LIB_RPC_SRCS) $(BUILD_DEFS)
	$(MKDIR) -p $(DEPS_DIR)
	$(MAKE) -f $(MAKE_DIR)/nvidia-modprobe.mk DESTDIR=$(DEPS_DIR) install
ifeq ($(WITH_NVCGO), yes)
	$(MAKE) -f $(MAKE_DIR)/nvcgo.mk DESTDIR=$(DEPS_DIR) VERSION_MAJOR=$(VERSION_MAJOR) VERSION=$(VERSION) LIB_NAME=$(LIBGO_NAME) install
endif
ifeq ($(WITH_LIBELF), no)
	$(MAKE) -f $(MAKE_DIR)/elftoolchain.mk DESTDIR=$(DEPS_DIR) install
endif
ifeq ($(WITH_TIRPC), yes)
	$(MAKE) -f $(MAKE_DIR)/libtirpc.mk DESTDIR=$(DEPS_DIR) install
endif

install: all
	$(INSTALL) -d -m 755 $(addprefix $(DESTDIR),$(includedir) $(bindir) $(libdir) $(docdir) $(libdbgdir) $(pkgconfdir))
	# Install header files
	$(INSTALL) -m 644 $(LIB_INCS) $(DESTDIR)$(includedir)
	# Install library files
	$(INSTALL) -m 644 $(LIB_STATIC) $(DESTDIR)$(libdir)
	$(INSTALL) -m 755 $(LIB_SHARED) $(DESTDIR)$(libdir)
	$(LN) -sf $(LIB_SONAME) $(DESTDIR)$(libdir)/$(LIB_SYMLINK)
ifeq ($(WITH_NVCGO), yes)
	$(INSTALL) -m 755 $(DEPS_DIR)$(libdir)/$(LIBGO_SHARED) $(DESTDIR)$(libdir)
	$(LN) -sf $(LIBGO_SONAME) $(DESTDIR)$(libdir)/$(LIBGO_SYMLINK)
endif
	$(LDCONFIG) -n $(DESTDIR)$(libdir)
	# Install debugging symbols
	$(INSTALL) -m 644 $(DEBUG_DIR)/$(LIB_SONAME) $(DESTDIR)$(libdbgdir)
	# Install configuration files
	$(MAKE_DIR)/$(LIB_PKGCFG).in "$(strip $(VERSION))" "$(strip $(LIB_LDLIBS_SHARED))" > $(DESTDIR)$(pkgconfdir)/$(LIB_PKGCFG)
	# Install binary files
	$(INSTALL) -m 755 $(BIN_NAME) $(DESTDIR)$(bindir)
	# Install documentation files
	$(INSTALL) -d -m 755 $(DESTDIR)$(docdir)/$(LIB_NAME)-$(VERSION)
	$(INSTALL) -m 644 $(DOC_FILES) $(DESTDIR)$(docdir)/$(LIB_NAME)-$(VERSION)

uninstall:
	# Uninstall header files
	$(RM) $(addprefix $(DESTDIR)$(includedir)/,$(notdir $(LIB_INCS)))
	# Uninstall library files
	$(RM) $(addprefix $(DESTDIR)$(libdir)/,$(LIB_STATIC) $(LIB_SHARED) $(LIB_SONAME) $(LIB_SYMLINK))
ifeq ($(WITH_NVCGO), yes)
	$(RM) $(addprefix $(DESTDIR)$(libdir)/,$(LIBGO_SHARED) $(LIBGO_SONAME) $(LIBGO_SYMLINK))
endif
	# Uninstall debugging symbols
	$(RM) $(DESTDIR)$(libdbgdir)/$(LIB_SONAME)
	# Uninstall configuration files
	$(RM) $(DESTDIR)$(pkgconfdir)/$(LIB_PKGCFG)
	# Uninstall binary files
	$(RM) $(DESTDIR)$(bindir)/$(BIN_NAME)
	# Uninstall documentation files
	$(RM) -r $(DESTDIR)$(docdir)/$(LIB_NAME)-$(VERSION)

dist: DESTDIR:=$(DIST_DIR)/$(LIB_NAME)_$(VERSION)$(addprefix -,$(TAG))
dist: install
	$(TAR) --numeric-owner --owner=0 --group=0 -C $(dir $(DESTDIR)) -caf $(DESTDIR)_$(ARCH).tar.xz $(notdir $(DESTDIR))
	$(RM) -r $(DESTDIR)

depsclean:
	$(RM) $(BUILD_DEFS)
	-$(MAKE) -f $(MAKE_DIR)/nvidia-modprobe.mk clean
ifeq ($(WITH_NVCGO), yes)
	-$(MAKE) -f $(MAKE_DIR)/nvcgo.mk clean
endif
ifeq ($(WITH_LIBELF), no)
	-$(MAKE) -f $(MAKE_DIR)/elftoolchain.mk clean
endif
ifeq ($(WITH_TIRPC), yes)
	-$(MAKE) -f $(MAKE_DIR)/libtirpc.mk clean
endif

mostlyclean:
	$(RM) $(LIB_OBJS) $(LIB_STATIC_OBJ) $(BIN_OBJS) $(DEPENDENCIES)

clean: mostlyclean depsclean

distclean: clean
	$(RM) -r $(DEPS_DIR) $(DIST_DIR) $(DEBUG_DIR)
	$(RM) $(LIB_RPC_SRCS) $(LIB_STATIC) $(LIB_SHARED) $(BIN_NAME)
	$(RM) -f $(SRCS_DIR)/nvc.h

deb: DESTDIR:=$(DIST_DIR)/$(LIB_NAME)_$(VERSION)_$(ARCH)
deb: prefix:=/usr
deb: libdir:=/usr/lib/@DEB_HOST_MULTIARCH@


PKG_VERS := $(VERSION_STRING)
PKG_REV := 1
deb: install
	$(CP) -T $(PKG_DIR)/deb $(DESTDIR)/debian
	cd $(DESTDIR) && dch --create --package="$(PKG_NAME)" \
        --newversion "$(PKG_VERS)-$(PKG_REV)" \
            "See https://gitlab.com/nvidia/container-toolkit/libnvidia-container/-/blob/$(REVISION)/CHANGELOG.md for the changelog" && \
    dch --controlmaint --release ""
	cd $(DESTDIR) && debuild -eDISTRIB -eSECTION --dpkg-buildpackage-hook='debian/prepare %v' -a$(ARCH) -us -uc -B
	cd $(DESTDIR) && (yes | debuild clean || yes | debuild -- clean)

rpm: DESTDIR:=$(DIST_DIR)/$(LIB_NAME)_$(VERSION)_$(ARCH)
rpm: all
	$(MKDIR) -p $(DIST_DIR)
	$(CP) -T $(PKG_DIR)/rpm $(DESTDIR)
	$(LN) -nsf $(CURDIR) $(DESTDIR)/BUILD
	$(MKDIR) -p $(DESTDIR)/RPMS && $(LN) -nsf $(DIST_DIR) $(DESTDIR)/RPMS/$(ARCH)
	cd $(DESTDIR) && \
		rpmbuild --clean --target=$(ARCH) -bb \
			-D"_topdir $(DESTDIR)" \
			-D "release_date $(shell date +'%a %b %d %Y')" \
			-D"version $(PKG_VERS)" \
			-D"release $(PKG_REV)" \
			-D"_major $(VERSION_MAJOR)" \
			-D "git_commit ${REVISION}" \
		SPECS/*.spec
	-cd $(DESTDIR) && rpmlint RPMS/*
