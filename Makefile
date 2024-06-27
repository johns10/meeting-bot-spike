# Variables
WHISPER_DIR = c_src/todo_app/whisper.cpp
WHISPER_LIB = $(WHISPER_DIR)/libwhisper.a
CXXFLAGS = -fPIC -I$(ERTS_INCLUDE_DIR) -I$(WHISPER_DIR) -std=c++11
LDFLAGS = -dynamiclib -undefined dynamic_lookup -L$(WHISPER_DIR) -lwhisper

PROJECT = nif
BUILDDIR = priv
SOURCEDIR = c_src/todo_app
TARGET = $(BUILDDIR)/$(PROJECT).so
SOURCES := $(SOURCEDIR)/nif.cpp $(SOURCEDIR)/transcribe.cpp
OBJS = $(patsubst $(SOURCEDIR)/%.cpp,$(BUILDDIR)/%.o,$(SOURCES))

$(info ERTS_INCLUDE_DIR: $(ERTS_INCLUDE_DIR))
$(info WHISPER_DIR: $(WHISPER_DIR))
$(info SOURCES: $(SOURCES))
$(info OBJ: $(OBJ))
$(info TARGET: $(TARGET))

# Default target
all: $(WHISPER_LIB) $(TARGET)

# Build whisper library
$(WHISPER_LIB):
	$(MAKE) -C $(WHISPER_DIR) libwhisper.a

# Compile and link
$(TARGET): $(OBJS) $(WHISPER_LIB)
	$(CXX) $(OBJS) $(LDFLAGS) -o $(TARGET)

# Compile source files to object files
$(BUILDDIR)/%.o: $(SOURCEDIR)/%.cpp $(BUILDDIR)
	$(CXX) $(CXXFLAGS) -c $< -o $@

# Create build directory if it doesn't exist
$(BUILDDIR):
	mkdir -p $(BUILDDIR)

# Clean up
clean:
	rm -f $(OBJ) $(TARGET)
# $(MAKE) -C $(WHISPER_DIR) clean 
