apt install python3-venv ninja-build build-essential pkg-config libglib2.0-dev flex bison
git clone https://gitlab.com/qemu-project/qemu.git
cd qemu
git submodule init
git submodule update --recursive
./configure
make
