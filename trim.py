import os

# Filenames (without extension) of glbs to spare from trimming.
# Add a glb here only if a scene loads it directly as a PackedScene at runtime.
KEEP = []

script_dir = os.path.dirname(os.path.abspath(__file__))

def delete_files(extension):
    for root, dirs, files in os.walk(script_dir):
        for file in files:
            if file.endswith(extension):
                file_path = os.path.join(root, file)
                if file.removesuffix(extension) in KEEP:
                    print(f"Skipping {file_path}")
                    continue
                print(f"Deleting {file_path}")
                os.remove(file_path)

delete_files(".glb")
delete_files(".glb.import")

print("Project has been trimmed.")
