class TextractService
  # Poll interval (seconds) for async job
  ASYNC_POLL_INTERVAL = 5
  ASYNC_POLL_MAX = 60 # max attempts, ~5min

  def extract_text_from_document(file_path)
    raise "File not found: #{file_path}" unless File.exist?(file_path)

    if pdf?(file_path)
      page_count = PDF::Reader.new(file_path).page_count
      if page_count == 1
        extract_from_pdf(File.read(file_path))
      else
        extract_from_pdf_async(file_path)
      end
    else
      extract_from_image(File.read(file_path))
    end
  end

  private

  # Images
  def extract_from_image(file_content)
    resp = $textract_client.detect_document_text(document: { bytes: file_content })
    process_blocks(resp.blocks)
  end

  # Single-page PDF
  def extract_from_pdf(file_content)
    resp = $textract_client.analyze_document(
      document: { bytes: file_content },
      feature_types: ['TABLES', 'FORMS']
    )
    process_blocks(resp.blocks)
  end

  # Multi-page PDF -> async + auto-poll
  def extract_from_pdf_async(file_path)
    s3_bucket = ENV['TEXTRACT_BUCKET'] || raise("Please set TEXTRACT_BUCKET")
    s3_key = "uploads/#{File.basename(file_path)}"

    # Upload PDF to S3
    $s3_client.put_object(bucket: s3_bucket, key: s3_key, body: File.open(file_path))

    # Start async Textract job
    resp = $textract_client.start_document_text_detection(
      document_location: { s3_object: { bucket: s3_bucket, name: s3_key } }
    )
    job_id = resp.job_id

    # Poll until job completes
    attempts = 0
    loop do
      sleep(ASYNC_POLL_INTERVAL)
      attempts += 1

      result = $textract_client.get_document_text_detection(job_id: job_id)
      case result.job_status
      when 'SUCCEEDED'
        blocks = result.blocks
        # Handle pagination
        next_token = result.next_token
        while next_token
          paged_result = $textract_client.get_document_text_detection(job_id: job_id, next_token: next_token)
          blocks.concat(paged_result.blocks)
          next_token = paged_result.next_token
        end
        return process_blocks(blocks)
      when 'FAILED'
        raise "Textract job failed: #{result.status_message}"
      else
        raise "Textract job timed out" if attempts >= ASYNC_POLL_MAX
      end
    end
  end

  def process_blocks(blocks)
    lines = blocks.select { |b| b.block_type == 'LINE' }.map(&:text)
    {
      text_lines: lines,
      total_lines: lines.length
    }
  end

  def pdf?(file_path)
    File.extname(file_path).downcase == '.pdf'
  end
end
