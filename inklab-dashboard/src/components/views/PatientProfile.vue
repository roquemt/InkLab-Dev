<template>
  <div class="profile-page">
    <div class="profile-header">
      <div class="avatar">SG</div>
      <div class="info">
        <h1>Sofía García Rodríguez</h1>
        <p>Patient ID: #2026-9901</p>
      </div>
    </div>
    
    <div class="metrics-grid">
      <div class="metric" v-for="m in ['Sex', 'Height', 'Age', 'Weight', 'BMI']" :key="m">
        <span>{{ m }}</span>
        <strong>--</strong>
      </div>
    </div>
    
    <div class="history-table">
      <!-- Standard Table for logs -->
    </div>
  </div>
</template>

<style scoped>
.profile-page { padding: 40px; }
.profile-header { display: flex; align-items: center; gap: 20px; margin-bottom: 40px; }
.avatar { width: 64px; height: 64px; background: var(--info); color: white; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-weight: 800; }
.metrics-grid { display: grid; grid-template-columns: repeat(5, 1fr); gap: 20px; }
.metric { padding: 20px; background: var(--ghost); border-radius: 8px; }
</style>