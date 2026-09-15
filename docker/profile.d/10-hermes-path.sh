# /etc/profile resets PATH and otherwise hides the image's Hermes CLI from
# terminal commands launched through `bash -l -c`.
case ":${PATH}:" in
  *:/opt/hermes/.venv/bin:*) ;;
  *) PATH="/opt/hermes/bin:/opt/hermes/.venv/bin:/opt/data/.local/bin:${PATH}" ;;
esac
export PATH
