# Copyright 2024-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

ROCM_VERSION=6.1
inherit cmake go-module toolchain-funcs

DESCRIPTION="Get up and running with Llama 3, Mistral, Gemma, and other language models."
HOMEPAGE="https://ollama.com"

if [[ ${PV} == *9999* ]]; then
    inherit git-r3
    EGIT_REPO_URI="https://github.com/pufferffish/ollama-vulkan.git"
else
    KEYWORDS="~amd64"
fi

LICENSE="MIT"
SLOT="0"

X86_CPU_FLAGS=(
    avx
    f16c
    avx2
    fma3
    avx512f
    avx512vbmi
    avx512_vnni
    avx512_bf16
    avx_vnni
    amx_tile
    amx_int8
)
CPU_FLAGS=( "${X86_CPU_FLAGS[@]/#/cpu_flags_x86_}" )
IUSE="${CPU_FLAGS[*]}"


DEPEND="
	>=dev-lang/go-1.23.4
	media-libs/shaderc
"

#RDEPEND="
#	acct-group/ollama
#	acct-user/ollama
#"

PATCHES=(
    "${FILESDIR}/${PN}-9999-include-cstdint.patch"
)

src_unpack() {
	if [[ "${PV}" == *9999* ]]; then
        git-r3_src_unpack
        go-module_live_vendor
    else
        go-module_src_unpack
    fi

	# Clean and sync the repository using Makefile.sync
	pushd "${S}" || die
	make -f Makefile.sync clean sync || die
	PATCHES=( "${FILESDIR}/${PN}-9999.patch" )
	popd || die
}

src_prepare() {
	cmake_src_prepare

	# Disable ccache in CMake
	sed -e "/set(GGML_CCACHE/s/ON/OFF/g" -i CMakeLists.txt || die

	# Handle CPU flags and architecture-specific optimizations
	if use amd64; then
        local cpu_flags=(
            avx f16c avx2 fma3 avx512f avx512vbmi avx512_vnni avx512_bf16
            avx_vnni amx_tile amx_int8
        )
        
        for flag in "${cpu_flags[@]}"; do
            if ! use "cpu_flags_x86_${flag}"; then
                sed -e "/ggml_add_cpu_backend_variant(${flag}/s/^/# /g" -i ml/backend/ggml/ggml/src/CMakeLists.txt || die
            fi
        done
    fi
}

src_configure() {
	local mycmakeargs=(
        -DGGML_CCACHE="no"
        -DGGML_BLAS="no"
    )
	mycmakeargs+=( -DCMAKE_CUDA_COMPILER="NOTFOUND" )
	mycmakeargs+=( -DCMAKE_HIP_COMPILER="NOTFOUND" )
	cmake_src_configure "${mycmakeargs[@]}"
	cmake --preset Vulkan || die
}

src_compile() {
	ego build
	cmake --build --preset Vulkan || die
	cmake_src_compile
}

src_install() {
	dobin ollama
	cmake_src_install
	doinitd "${FILESDIR}/ollama.init"
}

pkg_preinst() {
	keepdir /var/log/ollama
	fperms 777 /var/log/ollama
}

pkg_postinst() {
	einfo "Quick guide:"
	einfo "ollama serve"
	einfo "ollama run llama3:70b"
	einfo "See available models at https://ollama.com/library"
}

