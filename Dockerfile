FROM nousresearch/hermes-agent:latest

# Copy and install dependencies
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# Copy and run the patch script
COPY scripts/patch_gemini.py /tmp/patch_gemini.py
RUN python3 /tmp/patch_gemini.py && rm /tmp/patch_gemini.py
