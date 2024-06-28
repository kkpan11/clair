# The following builds a command in the "buildctl" variable that expects a
# context in the shell variable "src" and for the make variable "@" (the
# target) to be present. NB these purposefully are not immediately expanded.
output_args = type=oci \"name=$(IMAGE_NAME)\" oci-mediatypes=true compression=estargz rewrite-timestamp=true dest=$@
buildctl = buildctl build --frontend dockerfile.v0
buildctl += --opt platform=$(call splice,$(foreach a,$(CONTAINER_PLATFORMS),linux/$a))
# DEBUG toggles on the "plain" buildkit output.
ifdef DEBUG
buildctl += --progress plain
endif
buildctl += --opt build-arg:BUILDKIT_MULTI_PLATFORM=1
buildctl += $(strip $(foreach v,$(buildkit_passthru),$(if $($v),--opt build-arg:$v=$($v),)))
buildctl += --local context=$$src
buildctl += --local dockerfile=$$src
buildctl += --output $(call splice,$(output_args))
ifdef GITHUB_ACTIONS
buildctl += --export-cache type=gha,mode=max
buildctl += --import-cache type=gha
endif
ifndef BUILDKIT_HOST
# Add a (hopefully) helpful warning that's printed on buildctl use.
buildctl += $(warning 'BUILDKIT_HOST' is not defined)
endif

# The "container" target builds a container using the current state of the tree.
.PHONY: container
container: clair.oci
rm_pat += *.oci

# Clair.oci builds a container using the current state of the tree.
clair.oci: $(shell git ls-files -- ':*.go' ':go.mod' ':go.sum') Makefile Dockerfile
	src=.
	$(buildctl)

# Container-build creates a container using the current state of the tree and
# loads it into the container engine.
.PHONY: container-build
container-build: clair.oci
	$(docker) load <$<

# Clair-nightly.oci builds a container after applying our "nightly" modifications.
clair-nightly.oci: $(shell git ls-files -- ':*.go' ':go.mod' ':go.sum') Makefile Dockerfile
	$(MAKE) nightly-deps
	src=$$(mktemp -d)
	trap 'rm -rf $$src' EXIT
	git archive --add-file=go.mod --add-file=go.sum HEAD |
		tar -x -C "$$src"
	$(buildctl)

# The "dist-container" target builds a container using a created dist archive.
.PHONY: dist-container
dist-container: clair-$(VERSION).oci

# Clair-%.oci builds a container using the state of the tree at the commit
# indicated by the pattern.
clair-%.oci: clair-%.tar.gz
	src=$$(mktemp -d)
	trap 'rm -rf $$src' EXIT
	tar -xzf $< -C $$src --strip-components=1
	$(buildctl)

# The "dist-clairctl" target builds a container containing all the platforms
# where upstream supports clairctl.
.PHONY: dist-clairctl
dist-clairctl: clairctl-$(VERSION)

# Clairctl-% builds a set of clairctl binaries using the state of the tree at
# the commit indicated by the pattern
clairctl-%: clair-%.tar.gz
	src=$$(mktemp -d)
	trap 'rm -rf $$src' EXIT
	tar -xzf $< -C $$src --strip-components=1
	$(patsubst type=%,$(strip $(call splice,type=local dest=$@)),\
	$(patsubst platform=%,\
	platform=$(call splice,$(strip\
		$(foreach a,amd64 arm64 ppc64le s390x,linux/$a)\
		$(foreach a,amd64 arm64,darwin/$a)\
		$(foreach a,amd64 arm64,windows/$a)\
	)),\
	$(buildctl))) --opt target=ctl
rm_pat += clairctl-*
