# Normal-OJ 前端開發指南

本文檔說明 Normal-OJ 前端專案的開發規範、架構設計與最佳實踐。

## 📋 目錄

- [技術棧](#技術棧)
- [專案結構](#專案結構)
- [開發環境設定](#開發環境設定)
- [路由系統](#路由系統)
- [狀態管理](#狀態管理)
- [API 呼叫](#api-呼叫)
- [元件開發](#元件開發)
- [樣式設計](#樣式設計)
- [國際化 (i18n)](#國際化-i18n)
- [測試](#測試)
- [最佳實踐](#最佳實踐)

---

## 技術棧

### 核心框架

- **Vue.js 3** - 漸進式 JavaScript 框架
- **TypeScript** - 型別安全的 JavaScript 超集
- **Vite** - 快速的建構工具

### UI 與樣式

- **Tailwind CSS** - Utility-first CSS 框架
- **PostCSS** - CSS 處理工具

### 路由與狀態

- **Vue Router** - 官方路由管理器
- **Pinia** (或 Vuex) - 狀態管理

### 開發工具

- **pnpm** - 快速、節省空間的套件管理器
- **ESLint** - JavaScript Linter
- **Prettier** - 程式碼格式化工具
- **Playwright** - E2E 測試框架

---

## 專案結構

```
new-front-end/
├── src/
│   ├── pages/              # 頁面元件（檔案路由）
│   │   ├── index.vue       # 首頁 (/)
│   │   ├── login.vue       # 登入頁 (/login)
│   │   ├── problem/
│   │   │   ├── index.vue   # 題目列表 (/problem)
│   │   │   └── [id].vue    # 題目詳情 (/problem/:id)
│   │   ├── submission/
│   │   │   ├── index.vue   # 提交列表
│   │   │   └── [id].vue    # 提交詳情
│   │   └── course/
│   │
│   ├── components/         # 可重用元件
│   │   ├── common/         # 通用元件
│   │   │   ├── Button.vue
│   │   │   ├── Input.vue
│   │   │   └── Modal.vue
│   │   ├── problem/        # 題目相關元件
│   │   └── submission/     # 提交相關元件
│   │
│   ├── composables/        # Composition API 可重用邏輯
│   │   ├── useAuth.ts      # 認證相關
│   │   ├── useApi.ts       # API 呼叫
│   │   └── usePagination.ts
│   │
│   ├── models/             # API 互動層
│   │   ├── Auth.ts         # 認證 API
│   │   ├── Problem.ts      # 題目 API
│   │   └── Submission.ts   # 提交 API
│   │
│   ├── stores/             # Pinia Stores
│   │   ├── user.ts         # 使用者狀態
│   │   ├── problem.ts      # 題目狀態
│   │   └── ui.ts           # UI 狀態
│   │
│   ├── types/              # TypeScript 型別定義
│   │   ├── user.ts
│   │   ├── problem.ts
│   │   └── submission.ts
│   │
│   ├── utils/              # 工具函式
│   │   ├── format.ts       # 格式化函式
│   │   ├── validation.ts   # 驗證函式
│   │   └── constants.ts    # 常數定義
│   │
│   ├── i18n/               # 國際化
│   │   ├── en.json         # 英文翻譯
│   │   └── zh-TW.json      # 繁體中文翻譯
│   │
│   ├── assets/             # 靜態資源
│   │   ├── images/
│   │   └── styles/
│   │
│   ├── App.vue             # 根元件
│   └── main.ts             # 入口檔案
│
├── public/                 # 公開靜態資源
├── tests/                  # Playwright E2E 測試
├── index.html              # HTML 入口
├── vite.config.ts          # Vite 配置
├── tailwind.config.js      # Tailwind 配置
├── tsconfig.json           # TypeScript 配置
└── package.json            # npm 配置
```

---

## 開發環境設定

### 1. 前置需求

- **Node.js**: >= 20.17 (參考 `.nvmrc`)
- **pnpm**: 10.6.1+

### 2. 安裝依賴

```bash
cd new-front-end
pnpm install
```

### 3. 啟動開發伺服器

```bash
pnpm dev
```

開啟 http://localhost:8080

### 4. 其他指令

```bash
# 建置生產版本
pnpm build

# 預覽生產建置
pnpm preview

# 執行 Linter
pnpm lint

# 格式化程式碼
pnpm format

# 執行 E2E 測試
pnpm exec playwright test
```

---

## 路由系統

### 檔案路由

專案使用**檔案路由系統**，`src/pages/` 中的檔案會自動對應到路由：

| 檔案路徑 | 路由路徑 |
|----------|----------|
| `pages/index.vue` | `/` |
| `pages/about.vue` | `/about` |
| `pages/problem/index.vue` | `/problem` |
| `pages/problem/[id].vue` | `/problem/:id` |
| `pages/course/[name]/problem/[id].vue` | `/course/:name/problem/:id` |

### 動態路由參數

```vue
<!-- pages/problem/[id].vue -->
<script setup lang="ts">
import { useRoute } from 'vue-router'

const route = useRoute()
const problemId = route.params.id
</script>
```

### 程式化導航

```typescript
import { useRouter } from 'vue-router'

const router = useRouter()

// 導航到題目列表
router.push('/problem')

// 導航到特定題目
router.push(`/problem/${problemId}`)

// 導航並傳遞查詢參數
router.push({
  path: '/submission',
  query: { problemId: 123, status: 'AC' }
})
```

### 路由守衛

```typescript
// src/router/index.ts
router.beforeEach((to, from, next) => {
  const userStore = useUserStore()
  
  // 檢查是否需要登入
  if (to.meta.requiresAuth && !userStore.isLoggedIn) {
    next('/login')
  } else {
    next()
  }
})
```

---

## 狀態管理

### Pinia Store 結構

```typescript
// src/stores/user.ts
import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { User } from '@/types/user'

export const useUserStore = defineStore('user', () => {
  // State
  const user = ref<User | null>(null)
  const token = ref<string | null>(localStorage.getItem('token'))
  
  // Getters
  const isLoggedIn = computed(() => !!token.value)
  const isAdmin = computed(() => user.value?.role === 0)
  
  // Actions
  async function login(username: string, password: string) {
    const response = await Auth.login({ username, password })
    token.value = response.data.token
    user.value = response.data.user
    localStorage.setItem('token', token.value)
  }
  
  function logout() {
    token.value = null
    user.value = null
    localStorage.removeItem('token')
  }
  
  return {
    user,
    token,
    isLoggedIn,
    isAdmin,
    login,
    logout
  }
})
```

### 在元件中使用

```vue
<script setup lang="ts">
import { useUserStore } from '@/stores/user'

const userStore = useUserStore()

async function handleLogin() {
  await userStore.login(username, password)
  router.push('/courses')
}
</script>

<template>
  <div v-if="userStore.isLoggedIn">
    Welcome, {{ userStore.user?.username }}!
  </div>
</template>
```

---

## API 呼叫

### API Client 設定

```typescript
// src/models/api.ts
import axios from 'axios'
import { useUserStore } from '@/stores/user'

const api = axios.create({
  baseURL: import.meta.env.VITE_API_URL || '/api',
  timeout: 10000
})

// Request interceptor - 自動附加 token
api.interceptors.request.use(config => {
  const userStore = useUserStore()
  if (userStore.token) {
    config.params = { ...config.params, token: userStore.token }
  }
  return config
})

// Response interceptor - 錯誤處理
api.interceptors.response.use(
  response => response.data,
  error => {
    if (error.response?.status === 403) {
      // Token 過期，登出
      const userStore = useUserStore()
      userStore.logout()
      router.push('/login')
    }
    return Promise.reject(error)
  }
)

export default api
```

### Model 定義

```typescript
// src/models/Problem.ts
import api from './api'
import { Problem, ProblemListResponse } from '@/types/problem'

export const ProblemAPI = {
  // 取得題目列表
  async getList(params: {
    offset?: number
    count?: number
    course?: string
    tags?: string
  }): Promise<ProblemListResponse> {
    return api.get('/problem', { params })
  },
  
  // 取得題目詳情
  async get(id: number): Promise<Problem> {
    return api.get(`/problem/${id}`)
  },
  
  // 建立題目
  async create(data: Partial<Problem>): Promise<{ problemId: number }> {
    return api.post('/problem', data)
  },
  
  // 更新題目
  async update(id: number, data: Partial<Problem>): Promise<void> {
    return api.put(`/problem/${id}`, data)
  }
}
```

### Composable 封裝

```typescript
// src/composables/useProblem.ts
import { ref } from 'vue'
import { ProblemAPI } from '@/models/Problem'
import type { Problem } from '@/types/problem'

export function useProblem(id: number) {
  const problem = ref<Problem | null>(null)
  const loading = ref(false)
  const error = ref<Error | null>(null)
  
  async function fetch() {
    loading.value = true
    error.value = null
    try {
      problem.value = await ProblemAPI.get(id)
    } catch (e) {
      error.value = e as Error
    } finally {
      loading.value = false
    }
  }
  
  return {
    problem,
    loading,
    error,
    fetch
  }
}
```

### 在元件中使用

```vue
<script setup lang="ts">
import { useProblem } from '@/composables/useProblem'
import { onMounted } from 'vue'

const props = defineProps<{ id: number }>()
const { problem, loading, error, fetch } = useProblem(props.id)

onMounted(() => {
  fetch()
})
</script>

<template>
  <div v-if="loading">Loading...</div>
  <div v-else-if="error">Error: {{ error.message }}</div>
  <div v-else-if="problem">
    <h1>{{ problem.problemName }}</h1>
    <div v-html="problem.description"></div>
  </div>
</template>
```

---

## 元件開發

### Composition API (推薦)

```vue
<script setup lang="ts">
import { ref, computed } from 'vue'

// Props
const props = defineProps<{
  title: string
  count?: number
}>()

// Emits
const emit = defineEmits<{
  submit: [value: string]
  cancel: []
}>()

// State
const inputValue = ref('')

// Computed
const isValid = computed(() => inputValue.value.length > 0)

// Methods
function handleSubmit() {
  if (isValid.value) {
    emit('submit', inputValue.value)
  }
}
</script>

<template>
  <div class="card">
    <h2>{{ title }}</h2>
    <input v-model="inputValue" type="text" />
    <button @click="handleSubmit" :disabled="!isValid">
      Submit
    </button>
  </div>
</template>

<style scoped>
.card {
  @apply p-4 bg-white rounded-lg shadow;
}
</style>
```

### 元件命名規範

- **PascalCase**: 元件檔案名稱 (`UserProfile.vue`)
- **kebab-case**: 在模板中使用 (`<user-profile />`)
- **描述性命名**: 清楚表達元件用途

### Props 驗證

```vue
<script setup lang="ts">
import { PropType } from 'vue'

interface User {
  id: number
  name: string
}

const props = defineProps({
  user: {
    type: Object as PropType<User>,
    required: true
  },
  status: {
    type: String as PropType<'active' | 'inactive'>,
    default: 'active'
  },
  count: {
    type: Number,
    default: 0,
    validator: (value: number) => value >= 0
  }
})
</script>
```

---

## 樣式設計

### Tailwind CSS

專案使用 Tailwind CSS，優先使用 utility classes：

```vue
<template>
  <div class="flex items-center justify-between p-4 bg-white rounded-lg shadow-md">
    <h2 class="text-2xl font-bold text-gray-800">
      {{ title }}
    </h2>
    <button class="px-4 py-2 text-white bg-blue-500 rounded hover:bg-blue-600 transition">
      Click me
    </button>
  </div>
</template>
```

### 自訂主題

```javascript
// tailwind.config.js
module.exports = {
  theme: {
    extend: {
      colors: {
        primary: '#3B82F6',
        secondary: '#10B981',
        danger: '#EF4444',
        'noj-blue': '#2563EB'
      },
      spacing: {
        '72': '18rem',
        '84': '21rem',
        '96': '24rem'
      }
    }
  }
}
```

### Scoped Styles

當需要自訂 CSS 時使用 scoped:

```vue
<style scoped>
.custom-card {
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  border-radius: 12px;
}

/* Deep selector - 影響子元件 */
:deep(.child-component) {
  color: white;
}
</style>
```

---

## 國際化 (i18n)

### 設定

```typescript
// src/i18n/index.ts
import { createI18n } from 'vue-i18n'
import en from './en.json'
import zhTW from './zh-TW.json'

export const i18n = createI18n({
  legacy: false,
  locale: 'zh-TW',
  fallbackLocale: 'en',
  messages: {
    en,
    'zh-TW': zhTW
  }
})
```

### 翻譯檔案

```json
// src/i18n/zh-TW.json
{
  "nav": {
    "home": "首頁",
    "problem": "題目",
    "submission": "提交記錄",
    "course": "課程"
  },
  "problem": {
    "list": "題目列表",
    "difficulty": "難度",
    "submit": "提交"
  },
  "login": {
    "username": "使用者名稱",
    "password": "密碼",
    "submit": "登入",
    "error": "帳號或密碼錯誤"
  }
}
```

### 在元件中使用

```vue
<script setup lang="ts">
import { useI18n } from 'vue-i18n'

const { t, locale } = useI18n()

function switchLanguage() {
  locale.value = locale.value === 'zh-TW' ? 'en' : 'zh-TW'
}
</script>

<template>
  <div>
    <h1>{{ t('nav.home') }}</h1>
    <button @click="switchLanguage">
      {{ locale === 'zh-TW' ? 'English' : '中文' }}
    </button>
  </div>
</template>
```

---

## 測試

詳見 [TESTING_GUIDE.md](TESTING_GUIDE.md) 的 Frontend 測試章節。

---

## 最佳實踐

### 1. 使用 Composition API

```vue
<!-- Good -->
<script setup lang="ts">
import { ref, computed } from 'vue'

const count = ref(0)
const doubled = computed(() => count.value * 2)
</script>

<!-- Avoid: Options API -->
<script>
export default {
  data() {
    return { count: 0 }
  },
  computed: {
    doubled() {
      return this.count * 2
    }
  }
}
</script>
```

### 2. 型別安全

```typescript
// 定義明確的型別
interface Problem {
  problemId: number
  problemName: string
  tags: string[]
}

// 使用型別斷言
const problems = ref<Problem[]>([])

// Props 型別定義
const props = defineProps<{
  problem: Problem
}>()
```

### 3. 可重用邏輯提取

```typescript
// src/composables/usePagination.ts
export function usePagination(itemsPerPage = 20) {
  const currentPage = ref(1)
  const totalItems = ref(0)
  
  const totalPages = computed(() => 
    Math.ceil(totalItems.value / itemsPerPage)
  )
  
  const offset = computed(() => 
    (currentPage.value - 1) * itemsPerPage
  )
  
  return {
    currentPage,
    totalItems,
    totalPages,
    offset
  }
}
```

### 4. 錯誤處理

```typescript
async function submitCode() {
  try {
    loading.value = true
    await SubmissionAPI.create(code)
    showSuccess('提交成功')
    router.push('/submissions')
  } catch (error) {
    showError(error.message || '提交失敗')
  } finally {
    loading.value = false
  }
}
```

### 5. 效能優化

```vue
<script setup>
import { computed } from 'vue'

// 使用 computed 快取計算結果
const filteredProblems = computed(() => 
  problems.value.filter(p => p.tags.includes(selectedTag.value))
)

// 使用 v-once 對靜態內容
</script>

<template>
  <div v-once>
    <h1>{{ staticTitle }}</h1>
  </div>
  
  <!-- 使用 key 優化列表渲染 -->
  <div v-for="problem in filteredProblems" :key="problem.problemId">
    {{ problem.problemName }}
  </div>
</template>
```

---

## 相關文檔

- [TESTING_GUIDE.md](TESTING_GUIDE.md) - 測試指南
- [API_REFERENCE.md](API_REFERENCE.md) - API 參考
- [CONTRIBUTING.md](../new-front-end/CONTRIBUTING.md) - 貢獻指南

---

**最後更新：** 2025-11-29  
**維護者：** 2025 NTNU Software Engineering Team 1
