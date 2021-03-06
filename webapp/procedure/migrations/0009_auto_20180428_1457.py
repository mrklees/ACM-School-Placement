# Generated by Django 2.0.4 on 2018-04-28 19:57

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('procedure', '0008_auto_20180428_1436'),
    ]

    operations = [
        migrations.RenameField(
            model_name='runparameters',
            old_name='api_key',
            new_name='API_Key',
        ),
        migrations.RemoveField(
            model_name='runparameters',
            name='calculate_commutes',
        ),
        migrations.AddField(
            model_name='runparameters',
            name='calc_commutes',
            field=models.BooleanField(default=False, verbose_name='Calcute commute times? If you already calculated commutes in a previous run, re-calculating is not necessary.'),
        ),
    ]
