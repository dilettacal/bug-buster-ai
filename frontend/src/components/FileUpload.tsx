import { FileUploadProps } from '@/types/security';

/**
 * File upload button component for selecting Python files
 */
export default function FileUpload({ 
  fileName, 
  onFileUpload, 
  onAnalyzeCode, 
  isAnalyzing, 
  hasCode 
}: FileUploadProps) {
  return (
    <div className="flex items-center gap-4">
      {fileName && (
        <span className="text-sm text-accent bg-secondary/20 px-3 py-1 rounded-full">
          {fileName}
        </span>
      )}
      
      <input
        type="file"
        accept=".py"
        onChange={onFileUpload}
        className="hidden"
        id="file-upload"
      />
      
      <label
        htmlFor="file-upload"
        className="bg-primary hover:bg-primary/90 text-white px-4 py-2 rounded-lg cursor-pointer transition-colors font-medium"
      >
        Open python file...
      </label>
      
      <button
        onClick={onAnalyzeCode}
        disabled={!hasCode || isAnalyzing}
        className="bg-accent hover:bg-accent/90 disabled:bg-gray-400 disabled:cursor-not-allowed text-white px-6 py-2 rounded-lg transition-colors font-medium"
      >
        {isAnalyzing ? 'Analyzing...' : 'Analyze code'}
      </button>
    </div>
  );
}