/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
*/

export enum Emotion {
  Happy = 'Happy',
  Sad = 'Sad',
  Angry = 'Angry',
  Neutral = 'Neutral'
}

export interface TranscriptionSegment {
  speaker: string;
  timestamp: string;
  content: string;
  language: string;
  emotion?: Emotion;
}

export interface CRMReport {
  summary: string;
  keyPoints: string[];
  clientNeeds: string[];
  sentiment: string;
  nextSteps: string[];
}

export interface TranscriptionResponse {
  summary: string;
  segments: TranscriptionSegment[];
  crmReport?: CRMReport;
}

export type AppStatus = 'idle' | 'recording' | 'processing' | 'success' | 'error';

export interface AudioData {
  blob: Blob;
  base64?: string;
  mimeType: string;
  name?: string;
}