import { CodeInputProps } from '@/types/security';
import FileUpload from './FileUpload';

/**
 * Code input section with file upload and code display
 */
export default function CodeInput({
  codeContent,
  fileName,
  onFileUpload,
  onAnalyzeCode,
  isAnalyzing
}: CodeInputProps) {
  return (
    <div className="bg-white rounded-lg border border-border shadow-sm p-6 flex flex-col">
      <div className="flex items-center justify-between mb-4 flex-shrink-0">
        <label htmlFor="code-input" className="text-lg font-semibold text-foreground">
          Code to analyze
        </label>
        
        <FileUpload
          fileName={fileName}
          onFileUpload={onFileUpload}
          onAnalyzeCode={onAnalyzeCode}
          isAnalyzing={isAnalyzing}
          hasCode={!!codeContent}
        />
      </div>
      
      <textarea
        id="code-input"
        value={codeContent}
        readOnly
        placeholder="Select a Python file to display its contents here..."
        className="flex-1 w-full resize-none border border-border rounded-lg p-4 font-mono text-sm bg-input-bg focus:outline-none focus:ring-2 focus:ring-primary/50"
      />
    </div>
  );
}