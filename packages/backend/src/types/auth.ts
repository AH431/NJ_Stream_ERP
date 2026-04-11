/**
 * Auth 型別定義（對應 api-contract-auth.yaml FINAL v1.0）
 */

export interface JwtPayload {
  userId: number;
  role: string;
  iat?: number;
  exp?: number;
}

export interface TokenResponse {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
  role: string;
  userId: number;
}

export interface AuthErrorResponse {
  code: string;
  message: string;
}
