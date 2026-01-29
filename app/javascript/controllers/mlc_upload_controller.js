import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "dropzone", "fileInput", "fileName",
    "uploadSection", "pathSection",
    "checksumInput", "verifyBtn", "checksumResult",
    "binarySection", "binaryTree", "binaryPath",
    "storedPath"
  ]

  connect() {
    this.storedPath = null
  }

  toggleSource(event) {
    const sourceType = event.target.value
    if (sourceType === "upload") {
      this.uploadSectionTarget.classList.remove("hidden")
      this.pathSectionTarget.classList.add("hidden")
    } else {
      this.uploadSectionTarget.classList.add("hidden")
      this.pathSectionTarget.classList.remove("hidden")
    }
  }

  browse() {
    this.fileInputTarget.click()
  }

  dragover(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.add("border-blue-500", "bg-blue-50")
  }

  dragleave(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.remove("border-blue-500", "bg-blue-50")
  }

  drop(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.remove("border-blue-500", "bg-blue-50")

    const files = event.dataTransfer.files
    if (files.length > 0) {
      this.fileInputTarget.files = files
      this.handleFile()
    }
  }

  async handleFile() {
    const file = this.fileInputTarget.files[0]
    if (!file) return

    this.fileNameTarget.textContent = `Selected: ${file.name} (${this.formatSize(file.size)})`

    // Enable checksum verification
    if (this.hasVerifyBtnTarget) {
      this.verifyBtnTarget.disabled = false
    }

    // Upload file and get stored path
    await this.uploadFile(file)
  }

  async uploadFile(file) {
    const formData = new FormData()
    formData.append("tarball", file)

    try {
      this.fileNameTarget.textContent = `${file.name} (${this.formatSize(file.size)}) - Uploading...`

      const response = await fetch("/mlc_installations/upload", {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: formData
      })

      const data = await response.json()

      if (!response.ok) {
        throw new Error(data.error || "Upload failed")
      }

      this.storedPath = data.stored_path
      if (this.hasStoredPathTarget) {
        this.storedPathTarget.value = data.stored_path
      }
      this.fileNameTarget.textContent = `${file.name} (${this.formatSize(file.size)}) - Uploaded`
      this.fileNameTarget.classList.add("text-green-600")
      this.fileNameTarget.classList.remove("text-gray-500")

      // Auto-detect binaries after upload
      await this.detectBinaries()

    } catch (error) {
      this.fileNameTarget.textContent = `Upload failed: ${error.message}`
      this.fileNameTarget.classList.add("text-red-600")
      this.fileNameTarget.classList.remove("text-gray-500")
    }
  }

  async verifyChecksum() {
    const algorithm = document.querySelector('[name="mlc_installation[checksum_algorithm]"]').value
    const checksum = this.checksumInputTarget.value

    if (!algorithm || !checksum) {
      this.checksumResultTarget.textContent = "Please select algorithm and enter checksum"
      this.checksumResultTarget.className = "mt-2 text-sm text-yellow-600"
      return
    }

    if (!this.storedPath) {
      this.checksumResultTarget.textContent = "Please upload file first"
      this.checksumResultTarget.className = "mt-2 text-sm text-yellow-600"
      return
    }

    try {
      const response = await fetch(`/mlc_installations/verify_checksum`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({
          stored_path: this.storedPath,
          algorithm: algorithm,
          checksum: checksum
        })
      })

      const data = await response.json()

      if (data.verified) {
        this.checksumResultTarget.textContent = "Checksum verified successfully"
        this.checksumResultTarget.className = "mt-2 text-sm text-green-600"
        document.querySelector('[name="mlc_installation[checksum_verified]"]').value = "true"
      } else {
        this.checksumResultTarget.textContent = "Checksum mismatch!"
        this.checksumResultTarget.className = "mt-2 text-sm text-red-600"
      }
    } catch (error) {
      this.checksumResultTarget.textContent = `Verification failed: ${error.message}`
      this.checksumResultTarget.className = "mt-2 text-sm text-red-600"
    }
  }

  async detectBinaries() {
    if (!this.storedPath) {
      this.binaryTreeTarget.innerHTML = '<p class="text-yellow-600">Please upload file first</p>'
      return
    }

    try {
      this.binaryTreeTarget.innerHTML = '<p class="text-gray-500">Scanning tarball...</p>'

      const response = await fetch(`/mlc_installations/select_binary?stored_path=${encodeURIComponent(this.storedPath)}`, {
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        }
      })

      const data = await response.json()

      if (data.error) {
        this.binaryTreeTarget.innerHTML = `<p class="text-red-600">${data.error}</p>`
        return
      }

      this.renderBinaryTree(data.candidates)
    } catch (error) {
      this.binaryTreeTarget.innerHTML = `<p class="text-red-600">Error: ${error.message}</p>`
    }
  }

  renderBinaryTree(candidates) {
    if (candidates.length === 0) {
      this.binaryTreeTarget.innerHTML = '<p class="text-yellow-600">No MLC binaries found in tarball</p>'
      return
    }

    const html = candidates.map((c, i) => `
      <label class="flex items-center gap-2 p-2 hover:bg-gray-50 rounded cursor-pointer">
        <input type="radio" name="binary_candidate" value="${c.relative_path}" ${i === 0 ? 'checked' : ''}
               data-action="change->mlc-upload#selectBinary" class="rounded">
        <span class="font-mono text-sm">${c.relative_path}</span>
        <span class="text-xs text-gray-500">(${this.formatSize(c.size)})</span>
      </label>
    `).join('')

    this.binaryTreeTarget.innerHTML = html

    // Auto-select first candidate
    if (candidates.length > 0) {
      this.binaryPathTarget.value = candidates[0].relative_path
    }
  }

  selectBinary(event) {
    this.binaryPathTarget.value = event.target.value
  }

  formatSize(bytes) {
    if (bytes === 0) return '0 Bytes'
    const k = 1024
    const sizes = ['Bytes', 'KB', 'MB', 'GB']
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
  }
}
