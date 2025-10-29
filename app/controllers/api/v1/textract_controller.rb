class Api::V1::TextractController < ApplicationController
  ALLOWED_CONTENT_TYPES = %w[
    image/jpeg
    image/png
    image/tiff
    application/pdf
  ].freeze

  def upload
    file = params[:file]
    return render json: { error: 'No file uploaded' }, status: :bad_request if file.nil?
    unless ALLOWED_CONTENT_TYPES.include?(file.content_type)
      return render json: {
        error: 'Invalid file type',
        allowed_types: ALLOWED_CONTENT_TYPES
      }, status: :unprocessable_entity
    end

    file_path = Rails.root.join('tmp', file.original_filename)
    File.open(file_path, 'wb') { |f| f.write(file.read) }

    textract_service = TextractService.new
    result = textract_service.extract_text_from_document(file_path)

    render json: {
      file_type: file.content_type,
      file_name: file.original_filename,
      analysis: result
    }
  rescue => e
    render json: { error: 'Internal server error', details: e.message }, status: :internal_server_error
  ensure
    File.delete(file_path) if file_path && File.exist?(file_path)
  end
end
