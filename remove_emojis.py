import os
import re

# Comprehensive regex for emojis
EMOJI_PATTERN = re.compile(
    "["
    "\U0001f600-\U0001f64f"  # emoticons
    "\U0001f300-\U0001f5ff"  # symbols & pictographs
    "\U0001f680-\U0001f6ff"  # transport & map symbols
    "\U0001f1e0-\U0001f1ff"  # flags (iOS)
    "\U00002702-\U000027b0"  # dingbats
    "\U000024c2-\U0001f251"
    "\U0001f900-\U0001f9ff"  # supplemental symbols and pictographs
    "\U0001fa70-\U0001faff"  # symbols and pictographs extended-a
    "\U00002600-\U000026ff"  # miscellaneous symbols
    "\U00002300-\U000023ff"  # miscellaneous technical
    "]+", flags=re.UNICODE
)

def remove_emojis(text):
    return EMOJI_PATTERN.sub('', text)

def process_directory(directory, extension):
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith(extension):
                file_path = os.path.join(root, file)
                print(f"Processing {file_path}")
                try:
                    with open(file_path, 'r', encoding='utf-8') as f:
                        content = f.read()
                    
                    new_content = remove_emojis(content)
                    
                    if content != new_content:
                        with open(file_path, 'w', encoding='utf-8') as f:
                            f.write(new_content)
                        print(f"Removed emojis from {file}")
                except Exception as e:
                    print(f"Error processing {file_path}: {e}")

if __name__ == "__main__":
    process_directory('android/app/src/main/java', '.kt')
